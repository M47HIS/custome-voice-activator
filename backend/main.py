"""
Voice Module Backend — FastAPI server for coordination, actions, and dashboard.

Lightweight coordination layer. Transcription is done client-side via Voxtral.
Provides WebSocket endpoint for real-time status sync, REST API for action
management, and serves the web UI dashboard.
"""

import asyncio
import json
import logging
import os
import secrets
import time
from pathlib import Path
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Header, Depends
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# ── Configuration ───────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("voice-backend")

ENGINE = os.getenv("ENGINE", "voxtral")
LANGUAGE = os.getenv("LANGUAGE", "en")

DEFAULT_CONFIG_PATH = Path(__file__).parent / "config" / "default_actions.json"
DATA_DIR = Path(os.getenv("DATA_DIR", str(Path(__file__).parent / "data")))
ACTIONS_PATH = DATA_DIR / "actions.json"
STATIC_DIR = Path(__file__).parent / "static"

# ── App ─────────────────────────────────────────────────────────────────────────

app = FastAPI(title="Voice Module Backend", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080", "http://127.0.0.1:8080"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Global State ────────────────────────────────────────────────────────────────

class ServerState:
    """Thread-safe server state shared across WebSocket and REST handlers."""

    def __init__(self):
        self.state: str = "idle"  # idle | listening | transcribing
        self.transcription_history: list[dict] = []
        self.connected_clients: set[WebSocket] = set()
        self.engine: str = ENGINE
        self.last_activity: float = time.time()

    async def broadcast(self, message: dict) -> None:
        """Send a JSON message to all connected WebSocket clients."""
        data = json.dumps(message)
        dead: set[WebSocket] = set()
        tasks = []
        for ws in self.connected_clients:
            try:
                tasks.append(asyncio.create_task(ws.send_text(data)))
            except Exception:
                dead.add(ws)
        if dead:
            self.connected_clients -= dead
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def set_state(self, new_state: str) -> None:
        self.state = new_state
        self.last_activity = time.time()
        await self.broadcast({"type": "status", "state": new_state})

    def add_transcription(self, text: str) -> None:
        entry = {
            "text": text,
            "timestamp": time.time(),
            "iso": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }
        self.transcription_history.insert(0, entry)
        # Keep last 50
        if len(self.transcription_history) > 50:
            self.transcription_history = self.transcription_history[:50]


state = ServerState()

# ── Auth Token ──────────────────────────────────────────────────────────────────

AUTH_TOKEN_PATH = DATA_DIR / "auth_token"
_auth_token: str | None = None


def _load_or_create_auth_token() -> str:
    """Load existing auth token or create a new one on first startup."""
    global _auth_token
    if AUTH_TOKEN_PATH.exists():
        try:
            _auth_token = AUTH_TOKEN_PATH.read_text().strip()
            if not _auth_token:
                raise ValueError("empty token file")
            logger.info("Auth token loaded from file.")
            return _auth_token
        except Exception as e:
            logger.warning(f"Could not read auth token file ({e}), generating new one.")

    _auth_token = secrets.token_urlsafe(32)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    AUTH_TOKEN_PATH.write_text(_auth_token)
    logger.info("=" * 60)
    logger.info("AUTH TOKEN CREATED (store this safely):")
    logger.info(_auth_token)
    logger.info("=" * 60)
    # Print to stdout so `docker compose logs` shows it
    print(f"\n{'=' * 60}")
    print("AUTH TOKEN (copy and store securely):")
    print(_auth_token)
    print(f"{'=' * 60}\n")
    return _auth_token


def verify_auth_token(authorization: str | None = Header(None)) -> str:
    """FastAPI dependency: require valid Bearer token for mutation endpoints."""
    if _auth_token is None:
        raise HTTPException(status_code=500, detail="Auth token not configured on server.")
    if authorization is None or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header.")
    token = authorization.split(" ", 1)[1]
    if token != _auth_token:
        raise HTTPException(status_code=403, detail="Invalid auth token.")
    return token


# ── Startup ─────────────────────────────────────────────────────────────────────

@app.on_event("startup")
async def startup():
    logger.info(f"Voice Module backend starting (engine: {ENGINE})")
    # Load or create auth token
    _load_or_create_auth_token()
    # Load actions
    load_actions()
    logger.info("Backend ready.")


# ── Actions Management ──────────────────────────────────────────────────────────

_actions: list[dict] = []


def load_actions():
    global _actions
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if ACTIONS_PATH.exists():
        try:
            with open(ACTIONS_PATH) as f:
                _actions = json.load(f)
            logger.info(f"Loaded {len(_actions)} actions from {ACTIONS_PATH}")
        except (json.JSONDecodeError, PermissionError) as e:
            logger.warning(f"Could not parse {ACTIONS_PATH}: {e}")
            _actions = []
    elif DEFAULT_CONFIG_PATH.exists():
        logger.info(f"Seeding actions from {DEFAULT_CONFIG_PATH}")
        try:
            with open(DEFAULT_CONFIG_PATH) as f:
                _actions = json.load(f)
            save_actions()
            logger.info(f"Seeded {len(_actions)} default actions to {ACTIONS_PATH}")
        except (json.JSONDecodeError, PermissionError) as e:
            logger.warning(f"Could not load defaults: {e}")
            _actions = []
    else:
        logger.warning("No default actions file found, starting empty.")
        _actions = []


def save_actions():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with open(ACTIONS_PATH, "w") as f:
        json.dump(_actions, f, indent=2)


@app.get("/api/actions")
async def get_actions():
    return _actions


@app.post("/api/actions")
async def add_or_update_action(action: dict, _token: str = Depends(verify_auth_token)):
    if "name" not in action or "type" not in action:
        raise HTTPException(status_code=400, detail="Action requires 'name' and 'type' fields.")

    name = action["name"]
    existing = next((i for i, a in enumerate(_actions) if a["name"] == name), None)
    if existing is not None:
        _actions[existing] = action
        save_actions()
        return {"status": "updated", "name": name}
    else:
        _actions.append(action)
        save_actions()
        return {"status": "created", "name": name}


@app.delete("/api/actions/{name}")
async def delete_action(name: str, _token: str = Depends(verify_auth_token)):
    global _actions
    before = len(_actions)
    _actions = [a for a in _actions if a["name"] != name]
    if len(_actions) == before:
        raise HTTPException(status_code=404, detail=f"Action '{name}' not found.")
    save_actions()
    return {"status": "deleted", "name": name}


@app.get("/api/status")
async def get_status():
    return JSONResponse({
        "state": state.state,
        "engine": state.engine,
        "language": LANGUAGE,
        "connected_clients": len(state.connected_clients),
        "actions_loaded": len(_actions),
        "last_activity": state.last_activity,
    })


@app.get("/api/config")
async def get_config():
    return JSONResponse({
        "engine": ENGINE,
        "language": LANGUAGE,
        "ws_url": "ws://localhost:8080/ws",
        "actions": _actions,
        "auth_token": _auth_token,
    })


@app.get("/api/history")
async def get_history():
    return state.transcription_history[:20]


# ── WebSocket ───────────────────────────────────────────────────────────────────

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    state.connected_clients.add(ws)
    logger.info(f"WebSocket client connected ({len(state.connected_clients)} total)")

    # Send current state so new clients are in sync
    await ws.send_text(json.dumps({
        "type": "status",
        "state": state.state,
    }))

    role: str = "ui"  # "client" or "ui"

    try:
        while True:
            message = await ws.receive()

            if "text" in message:
                data = json.loads(message["text"])
                msg_type = data.get("type")

                if msg_type == "hello":
                    role = data.get("role", "ui")
                    logger.info(f"Client registered as '{role}'")
                    await ws.send_text(json.dumps({
                        "type": "welcome",
                        "role": role,
                        "engine": state.engine,
                    }))

                elif msg_type == "status":
                    # Client reports its state change
                    new_state = data.get("state", "idle")
                    await state.set_state(new_state)
                    logger.info(f"State changed to '{new_state}' by {role}")

                elif msg_type == "transcription":
                    # Client sends transcription result for history/logging
                    text = data.get("text", "")
                    is_final = data.get("is_final", True)
                    if text and is_final:
                        state.add_transcription(text)
                    # Broadcast to all observers (UI dashboards)
                    await state.broadcast({
                        "type": "transcription",
                        "text": text,
                        "is_final": is_final,
                    })
                    logger.info(f"Transcription received: '{text[:80]}...'" if len(text) > 80 else f"Transcription received: '{text}'")

                elif msg_type == "ping":
                    await ws.send_text(json.dumps({"type": "pong"}))

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        state.connected_clients.discard(ws)


# ── Static Files ────────────────────────────────────────────────────────────────

@app.get("/")
async def serve_index():
    return FileResponse(STATIC_DIR / "index.html")


# Must be last
app.mount("/", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")
