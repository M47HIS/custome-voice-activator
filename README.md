# Voice Module

**macOS always-on voice-to-text hotkey trigger with Voxtral transcription.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python)](https://python.org)
[![Voxtral](https://img.shields.io/badge/Powered_by-Voxtral-FF6B35?logo=apple)](https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit)
[![FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![Swift](https://img.shields.io/badge/UI-SwiftUI-F05138?logo=swift)](https://developer.apple.com/swiftui/)

Hold a hotkey, speak, release — and your speech is transcribed locally via
**[Voxtral](https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit)**
on Apple Neural Engine, then sent to a **configurable action**: open a terminal
with `opencode`, copy to clipboard, trigger a webhook, or run any command.

All processing happens on your machine. No audio leaves your Mac.

> **Primary UI: a native macOS menu-bar app.** The web dashboard has been
> removed from the product surface. The backend is a headless local API.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                              macOS                                    │
│                                                                      │
│  ┌──────────────────────────┐    REST + WebSocket   ┌────────────────┐ │
│  │ VoiceActivator.app       │ ◄───────────────────► │  Backend       │ │
│  │ (Swift menu-bar app)     │    settings, status   │  (OrbStack)    │ │
│  │                          │                       │                │ │
│  │ • ProcessSupervisor      │                       │  FastAPI:8080  │ │
│  │ • BackendClient          │                       │  Actions       │ │
│  │ • Settings window        │                       │  History       │ │
│  │ • Native hotkey manager  │                       │  (no UI)       │ │
│  └──────────────┬───────────┘                       └───────▲────────┘ │
│                 │ spawns                                        │       │
│                 ▼                                               │       │
│  ┌──────────────────────────┐                       ┌──────────┴─────┐ │
│  │  voice_client.py         │ ◄──── WebSocket ─────►│   Backend     │ │
│  │  (Python worker)         │   status / actions    │                │ │
│  │                          │                       │                │ │
│  │  • sounddevice (mic)     │                       │                │ │
│  │  • Voxtral (Apple MLX)   │                       │                │ │
│  │  • Action runner         │                       │                │ │
│  └──────────────────────────┘                       └────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

**Three components, one Mac:**

1. **VoiceActivator** — Swift menu-bar app. Primary UI. Manages the lifecycle of the other two.
2. **Backend** — FastAPI in Docker, bound to `127.0.0.1:8080`. Headless coordination: actions, settings, transcription history, status relay.
3. **Python worker** — `client/voice_client.py --worker`. Mic + Voxtral transcription + action execution. Speaks to the backend over WebSocket and receives recording commands from the Swift app.

---

## Quick Start

### 1. Prerequisites

- **macOS 13+** (for the menu-bar app)
- **OrbStack** (or Docker Desktop) installed and running
  ```bash
  brew install orbstack
  ```
- **Python 3.11+** with pip
- **Xcode 15+** (or the Swift toolchain) — needed to build the menu-bar app
- [Homebrew](https://brew.sh) (recommended)

### 2. Install client dependencies

```bash
# System dependency for audio
brew install portaudio

# Python packages
cd client
pip3 install -r requirements.txt

# Voxtral (Apple MLX transcription engine)
pip3 install mlx-audio
```

### 3. Build the menu-bar app

```bash
./script/build_and_run.sh
```

This builds the Swift app in release mode, stages `dist/VoiceActivator.app`,
and launches it. You should see a waveform icon appear in the menu bar.

The app **auto-starts the backend (Docker) and the Python worker** on first
launch. Click the menu-bar icon to access Settings, view status, or open logs.

### 4. Grant macOS Permissions

VoiceActivator owns the global hotkey. The Python worker owns audio capture
and transcription. See [Permissions Setup](#permissions-setup).

### 5. Hold the hotkey

Default hotkey: **Cmd+Shift+Space** (hold to record, release to transcribe).

> First run downloads the Voxtral model (~2GB, cached in `~/.cache/huggingface/`).

---

## The Menu-Bar App

The menu-bar icon shows the current state:

| Icon | State |
|------|-------|
| `waveform.circle` | Idle (default) |
| `waveform.circle.fill` | Listening (recording) |
| `waveform.path.ecg` | Transcribing |
| `exclamationmark.triangle.fill` | Error |
| `xmark.circle.fill` | Offline (backend not running) |

**Click the icon** to open a menu with:

- **Status** — backend and client health dots
- **Start / Stop / Restart** — manage both processes
- **Settings…** — hotkey recorder (NSEvent-based), mode (hold/toggle), action dropdown
- **Open Logs** — Finder at `~/Library/Logs/VoiceModule/`
- **Open Config Folder** — Finder at `~/.config/voice-module/`
- **Quit**

### Settings window

- **Hotkey recorder** — Click the field, press a key combination. Requires at least one modifier (Cmd/Ctrl/Alt/Shift). The captured combo is serialized to the same format (`cmd+ctrl+alt+shift+key`) that the Python parser accepts.
- **Mode** — Hold (push-to-talk) or Toggle (press to start, press again to stop).
- **Action** — dropdown populated from the backend's `/api/actions` endpoint.
- **Status** — read-only display of backend and client states.
- **Permissions** — Accessibility, Microphone, Notifications, and quick links to System Settings.
- **Logs** — read-only path display + "Reveal in Finder" button.

Saving posts to `POST /api/settings` with a Bearer token.

---

## Features

### Powered by Voxtral

Transcription uses **Voxtral-Mini-4B-Realtime** on Apple MLX.
It runs directly on the Mac's Apple Neural Engine — no cloud, no Docker GPU,
no API keys. Fast, private, and always available.

### Configurable Actions

Actions define what happens with transcribed text. Manage them via:

- **Settings window → Action dropdown** (read from backend)
- **REST API**: `POST /api/actions` (requires auth)
- **Config file**: `backend/config/default_actions.json`

**Built-in action types:**

| Type | Description |
|------|-------------|
| `terminal_command` | Open Terminal and run a command. Paste text automatically. |
| `clipboard` | Copy transcribed text to clipboard. |
| `open_app` | Open a macOS app with the text. |
| `http_request` | Send the text via HTTP POST/GET (webhook, API, etc.) |

**Default actions included:**
- **opencode** — Open Terminal with opencode, paste transcribed text
- **clipboard** — Copy to clipboard
- **shell** — Run `echo "{text}"` in Terminal
- **notification** — Show macOS notification with transcribed text
- **http_post** — Send to a webhook (configure your URL)

### ProcessSupervisor

The Swift app's `ProcessSupervisor` is the single source of truth for process
lifecycle. It:

- Resolves OrbStack (`orb`) or Docker (`docker`) at launch — prefers OrbStack.
- Runs `docker compose up -d --build` on first start, polls `/api/status` until healthy.
- Spawns `python3 client/voice_client.py` as a subprocess, captures stdout/stderr to `~/.local/log/voice-module/`.
- Stops the backend with `docker compose stop voice-backend` (preserves the container) and restarts with `docker compose restart`.
- Sends SIGTERM to the client, then SIGKILL after a 1.5s grace period.
- Auto-reconnects the WebSocket and re-fetches settings/actions on launch.

Logs are mirrored to `~/Library/Logs/VoiceModule/menu-bar.log` (also visible
in Console.app under subsystem `com.voicemodule.activator`).

---

## Configuration

### Client Config

`~/.config/voice-module/config.json` (created automatically on first run):

```json
{
    "hotkey": "cmd+shift+space",
    "mode": "hold",
    "sample_rate": 16000,
    "language": "en",
    "beep": true,
    "min_duration": 0.3,
    "backend_url": "ws://localhost:8080/ws",
    "backend_http": "http://localhost:8080",
    "action": "opencode",
    "engine": "voxtral"
}
```

The Swift app mirrors its **own** config (hotkey, mode, action) via the
backend at `127.0.0.1:8080/api/settings`. The Python worker reads action and
engine settings on startup; the Swift app owns the global hotkey and sends
recording commands to the worker.

### Hotkey Format

`modifier+modifier+key` — at least one modifier required.

**Modifiers:** `cmd`, `ctrl`, `alt`/`option`, `shift`
**Special keys:** `space`, `tab`, `enter`, `esc`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `home`, `end`, `page_up`, `page_down`, `f1`–`f20`
**Regular keys:** any single character (`a`, `9`, `.`)

Examples: `cmd+shift+space`, `ctrl+alt+o`, `cmd+shift+r`

### Backend Environment

Configured in `docker-compose.yml` or via a `.env` file:

```env
ENGINE=voxtral
LANGUAGE=en
```

---

## CLI Reference

### Menu-bar app (Swift)

```bash
./script/build_and_run.sh          # build + launch dist/VoiceActivator.app
./script/build_and_run.sh --verify # build + launch + process check
./script/build_and_run.sh --install # copy dist/VoiceActivator.app to /Applications
pkill -x VoiceActivator            # stop
```

### Client (Python, used internally)

```bash
# Defaults
python3 client/voice_client.py

# Override hotkey
python3 client/voice_client.py --hotkey "ctrl+alt+o"

# Override action
python3 client/voice_client.py --action clipboard

# Debug output
python3 client/voice_client.py --debug

# Worker mode used by VoiceActivator.app
python3 client/voice_client.py --worker

# List audio devices
python3 client/voice_client.py --list-devices
```

### Backend API

```bash
# Check health
curl http://localhost:8080/api/status

# List actions
curl http://localhost:8080/api/actions

# Get settings
curl http://localhost:8080/api/settings

# Save settings (requires Bearer token)
curl -X POST http://localhost:8080/api/settings \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"hotkey":"cmd+shift+r","mode":"hold","action":"clipboard"}'

# Add an action
curl -X POST http://localhost:8080/api/actions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"name":"my-shell","description":"Run my script","type":"terminal_command","config":{"command":"~/myscript.sh {text}"}}'

# Delete an action
curl -X DELETE http://localhost:8080/api/actions/my-shell \
  -H "Authorization: Bearer <token>"

# Get full config (including the auth token — unauthenticated)
curl http://localhost:8080/api/config

# Get transcription history
curl http://localhost:8080/api/history
```

### Legacy Standalone

The legacy launcher (`start.sh`) and the standalone `voice_module.py` are
preserved for manual / scripted use (CI, headless servers). Prefer the
menu-bar app for daily use.

```bash
# Without Docker (uses local faster-whisper directly)
python3 voice_module.py
python3 voice_module.py --model tiny.en --mode toggle
```

---

## Permissions Setup

### Accessibility

VoiceActivator uses a native macOS hotkey registration path. If hotkeys or
paste/automation actions are blocked, grant Accessibility to the installed app.

1. **System Settings → Privacy & Security → Accessibility**
2. Click **+** and add `VoiceActivator.app`
3. Toggle must be **ON**

> Legacy/manual Python mode still uses `pynput`. If you run Python directly,
> you may need to add the Python binary:
> `/opt/homebrew/opt/python@3.11/libexec/bin/python3`

### Microphone (required)

The first time you trigger a recording, macOS prompts for permission.
If it doesn't:

1. **System Settings → Privacy & Security → Microphone**
2. Enable the Python process used by the worker. If you install/run the app
   bundle directly, also enable `VoiceActivator.app` if macOS lists it.

### Notifications (optional)

For the optional "Recording..." / "Transcribed: ..." banners. Grant
`VoiceActivator.app` or the Python worker in **System Settings → Notifications**
if macOS prompts.

---

## Troubleshooting

### Menu-bar icon doesn't appear

```bash
# Is the binary built?
ls macos/VoiceActivator/.build/release/VoiceActivator

# Run with logs visible
macos/VoiceActivator/.build/release/VoiceActivator
# or
tail -f ~/Library/Logs/VoiceModule/menu-bar.log
```

### Backend won't start

```bash
# Check OrbStack/Docker is running
docker info || orb info

# Check logs
docker compose logs -f

# Rebuild
docker compose build --no-cache
docker compose up -d
```

### "Hotkey not working"

- Verify Accessibility permissions (see above)
- Check no other app is using the same hotkey
- Run with `python3 client/voice_client.py --debug` to see key events

### "No audio / recording too short"

- Check Microphone permissions
- Verify your mic: `python3 client/voice_client.py --list-devices`
- If no default mic, set one in **System Settings → Sound → Input**

### "Voxtral model download failed"

Voxtral downloads automatically on first transcription (~2GB).
Check `~/.cache/huggingface/` for model files.
The model is `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`.

### "Connection refused"

The backend isn't running. From the menu bar: **Start**. From the terminal:

```bash
docker compose up -d
docker compose logs -f
```

---

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development setup guide.

```bash
git clone https://github.com/mathisnaud/voice-module.git
cd voice-module

# Backend (with hot reload)
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8080

# Python client
cd ../client
pip install -r requirements.txt
pip install mlx-audio
python3 voice_client.py --debug

# Menu-bar app (Swift)
./script/build_and_run.sh
```

---

## Menu-Bar App vs Standalone

| Feature | Menu-Bar App (Swift) + Docker | Standalone (`voice_module.py`) |
|---------|-------------------------------|--------------------------------|
| UI | Native macOS menu bar (waveform icon) | Terminal only |
| Setup | Build Swift app + Docker | `pip install` only |
| Transcription | Voxtral on client (Apple MLX) | Local faster-whisper |
| RAM usage | Backend ~50MB, Voxtral in client | Model in main process |
| Settings UI | Native window (hotkey recorder, mode, action) | Config file only |
| Action config | Live from backend (`/api/actions`) | Hardcoded to opencode |
| Multi-client | Yes (any client on network) | No |
| Best for | Daily use, multi-action, configurable | Quick single-user, no Docker |

---

## Optional: Install and Launch at Login

```bash
./script/build_and_run.sh --install
open /Applications/VoiceActivator.app
```

The Settings window includes a **Launch at login** control using macOS
`SMAppService`. If macOS reports "requires approval", approve VoiceActivator in
**System Settings → General → Login Items**.

The menu-bar app will start the backend and Python worker automatically.

---

## Security

### Localhost-Only Binding

The backend binds to `127.0.0.1:8080` on the host via Docker port mapping.
It is **not exposed on the local network**. Only processes on the same machine
can reach the API and WebSocket.

### Auth Token

The backend requires authentication for action mutations
(`POST /api/actions`, `DELETE /api/actions/{name}`, `POST /api/settings`).
On first startup, a random 32-byte auth token is generated and stored in the
Docker volume at `/data/auth_token`.

**Finding the token (host side):**

```bash
# View in startup logs (printed to stdout on first run)
docker compose logs voice-backend | grep "AUTH TOKEN"

# Read directly from the container
docker compose exec voice-backend cat /data/auth_token
```

**How the menu-bar app authenticates:**

1. On first launch, the app calls `GET /api/config` (unauthenticated) and reads the `auth_token` field.
2. The token is cached at `~/Library/Application Support/VoiceModule/auth_token` for subsequent launches.
3. All `POST` requests include `Authorization: Bearer <token>`.

**Where the token lives:**

| Location | Path |
|----------|------|
| Backend (Docker volume) | `/data/auth_token` (inside container) |
| Menu-bar app cache | `~/Library/Application Support/VoiceModule/auth_token` |
| Python client cache | `~/.config/voice-module/config.json` → `auth_token` key |

**Notes:**

- `GET` endpoints (`/api/status`, `/api/config`, `/api/actions`, `/api/history`) are **read-only** and do not require authentication.
- WebSocket connections are accepted without authentication; the WebSocket relays status/transcription data only.
- WebSocket messages from untrusted sources cannot mutate settings or actions — the only mutations are REST `POST`/`DELETE` calls that require the Bearer token.

### CORS

CORS is restricted to `http://localhost:8080` and `http://127.0.0.1:8080` only.
Cross-origin requests from other origins are rejected.

---

## License

MIT © 2026 [Mathis Naud](https://github.com/mathisnaud)
