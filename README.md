# Voice Module

**macOS always-on voice-to-text hotkey trigger with Voxtral transcription.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python)](https://python.org)
[![Voxtral](https://img.shields.io/badge/Powered_by-Voxtral-FF6B35?logo=apple)](https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit)
[![FastAPI](https://img.shields.io/badge/FastAPI-✔-009688?logo=fastapi)](https://fastapi.tiangolo.com)

Hold a hotkey, speak, release — and your speech is transcribed locally via
**[Voxtral](https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit)**
on Apple Neural Engine, then sent to a **configurable action**: open a terminal
with `opencode`, copy to clipboard, trigger a webhook, or run any command.

All processing happens on your machine. No audio leaves your Mac.

---

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                         macOS                                 │
│                                                               │
│  ┌──────────────────────┐        WebSocket       ┌──────────────────────┐
│  │  Client               │ ◄───────────────────► │  Backend (OrbStack)   │
│  │                       │   status/transcription│                      │
│  │  pynput (hotkeys)     │                       │  FastAPI :8080        │
│  │  sounddevice (mic)    │   ◄── actions ──►     │  Actions + History    │
│  │  Voxtral (Apple MLX)  │                       │  Web UI dashboard     │
│  │  Action runner        │                       │                      │
│  └──────────────────────┘                       └──────────────────────┘
│                                                               │
│  Transcribe locally → Send result → Execute action            │
└───────────────────────────────────────────────────────────────┘
```

**Voxtral runs on the Mac client** (Apple Neural Engine), not in Docker.
The backend is lightweight — just coordination, actions, and the web dashboard.

---

## Quick Start

### 1. Prerequisites

- **macOS** (for the native client + Apple Neural Engine)
- **OrbStack** (or Docker Desktop) installed and running
  ```bash
  brew install orbstack
  ```
- **Python 3.11+** with pip
- [Homebrew](https://brew.sh) (recommended)

### 2. Start the Backend

```bash
docker compose up -d
```

The backend starts almost instantly (no model download needed).
Open **http://localhost:8080** to see the web dashboard.

### 3. Install Client Dependencies

```bash
# System dependency for audio
brew install portaudio

# Python packages
cd client
pip3 install -r requirements.txt

# Voxtral (Apple MLX transcription engine)
pip3 install mlx-audio
```

### 4. Grant macOS Permissions

The client needs **Accessibility** (for global hotkeys) and **Microphone**
access. See [Permissions Setup](#permissions-setup) below.

### 5. Start the Client

```bash
python3 client/voice_client.py
```

Hold **Cmd+Shift+Space**, speak, release → transcription + action!

> First run downloads the Voxtral model (~2GB, cached in `~/.cache/huggingface/`).

---

## Features

### Powered by Voxtral

Transcription uses **Voxtral-Mini-4B-Realtime** on Apple MLX.
It runs directly on the Mac's Apple Neural Engine — no cloud, no Docker GPU,
no API keys. Fast, private, and always available.

### Configurable Actions

Actions define what happens with transcribed text. Manage them via:

- **Web UI**: `http://localhost:8080` → Actions panel
- **REST API**: `POST /api/actions`
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

### Web Dashboard

The backend serves a real-time dashboard at **http://localhost:8080**:

- **Waveform visualization** — Animated audio bars react to recording state
- **Status indicator** — Idle / Recording (pulsing) / Transcribing
- **Action manager** — Create, edit, delete actions with a form UI
- **Transcription history** — Last 50 transcriptions with timestamps
- **System status** — Engine info, connected clients, last activity

### Microphone Animation

The waveform animates based on the recording state:

- **Idle**: Subtle breathing bars, barely visible
- **Recording**: Vibrant dancing bars with warm accent glow + pulse ring
- **Transcribing**: Bars gently breathe in amber tones
- **Done**: Returns to idle state

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

| Key | Description |
|-----|-------------|
| `hotkey` | Global hotkey (format: `modifier+modifier+key`) |
| `mode` | `hold` (push-to-talk) or `toggle` |
| `min_duration` | Skip recordings shorter than this (seconds) |
| `beep` | Play system beep on recording start |
| `action` | Default action name to execute |
| `engine` | `voxtral` (local MLX) or `backend` (deprecated — backend no longer transcribes) |
| `backend_url` | WebSocket endpoint for coordination |

### Hotkey Format

`modifier+modifier+key` — at least one modifier required.

**Modifiers:** `cmd`, `ctrl`, `alt`/`option`, `shift`
**Special keys:** `space`, `tab`, `enter`, `esc`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `f1`–`f20`
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

### Client

```bash
# Start with defaults
python3 client/voice_client.py

# Change hotkey
python3 client/voice_client.py --hotkey "ctrl+alt+o"

# Change action
python3 client/voice_client.py --action clipboard

# Custom backend URL
python3 client/voice_client.py --backend ws://192.168.1.100:8080/ws

# Debug mode
python3 client/voice_client.py --debug

# List audio devices
python3 client/voice_client.py --list-devices
```

### Backend API

```bash
# Check health
curl http://localhost:8080/api/status

# List actions
curl http://localhost:8080/api/actions

# Add an action
curl -X POST http://localhost:8080/api/actions \
  -H "Content-Type: application/json" \
  -d '{"name":"my-shell","description":"Run my script","type":"terminal_command","config":{"command":"~/myscript.sh {text}"}}'

# Delete an action
curl -X DELETE http://localhost:8080/api/actions/my-shell

# Get config
curl http://localhost:8080/api/config

# Get transcription history
curl http://localhost:8080/api/history
```

### Legacy Standalone

```bash
# Without Docker (uses local faster-whisper directly)
python3 voice_module.py
python3 voice_module.py --model tiny.en --mode toggle
```

---

## Permissions Setup

### Accessibility (required)

Allows global hotkey detection.

1. **System Settings → Privacy & Security → Accessibility**
2. Click **+** and add your **Terminal.app** (or terminal emulator)
3. Toggle must be **ON**

> If you run Python directly, you may need to add the Python binary:
> `/opt/homebrew/opt/python@3.11/libexec/bin/python3`

### Microphone (required)

The first time you trigger a recording, macOS prompts for permission.
If it doesn't:

1. **System Settings → Privacy & Security → Microphone**
2. Enable for **Terminal** or **python3**

---

## Troubleshooting

### Backend won't start

```bash
# Check OrbStack/Docker is running
docker ps

# Check logs
docker compose logs -f

# Rebuild
docker compose build --no-cache
docker compose up -d
```

### "Hotkey not working"

- Verify Accessibility permissions (see above)
- Check no other app is using the same hotkey
- Run with `--debug` to see key events

### "No audio / recording too short"

- Check Microphone permissions
- Verify your mic: `python3 client/voice_client.py --list-devices`
- If no default mic, set one in **System Settings → Sound → Input**

### "Voxtral model download failed"

Voxtral downloads automatically on first transcription (~2GB).
Check `~/.cache/huggingface/` for model files.
The model is `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`.

### "Connection refused"

The backend isn't running:

```bash
# Is OrbStack/Docker running?
docker info

# Start the backend
docker compose up -d

# Check logs
docker compose logs -f
```

### Web UI not loading

- Make sure port 8080 isn't in use by another app
- Check: `lsof -i :8080`
- Try a different port: edit `docker-compose.yml` ports to `8081:8080`

---

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for full development setup guide.

```bash
# Clone and start
git clone https://github.com/mathisnaud/voice-module.git
cd voice-module

# Backend dev (with hot reload)
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8080

# Web UI dev — edit static/ files, refresh browser

# Client dev
cd client
python3 voice_client.py --debug
```

---

## Standalone vs Docker

| Feature | Standalone (`voice_module.py`) | Docker Client/Server |
|---------|-------------------------------|---------------------|
| Setup | `pip install` only | Docker + pip |
| Transcription | Local faster-whisper | Voxtral on client (Apple MLX) |
| RAM usage | Model in main process | Backend ~50MB, Voxtral in client |
| Web UI | ❌ | ✅ |
| Action config | ❌ (hardcoded to opencode) | ✅ (configurable via UI/API) |
| Multi-client | ❌ | ✅ (any client on network) |
| Best for | Quick single-user | Always-on, multi-use, configurable |

---

## Optional: LaunchAgent (Auto-start)

Create `~/Library/LaunchAgents/com.voicemodule.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.voicemodule.client</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/python3</string>
        <string>/path/to/client/voice_client.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/voicemodule.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/voicemodule.err</string>
</dict>
</plist>
```

Then: `launchctl load ~/Library/LaunchAgents/com.voicemodule.plist`

---

## Security

### Localhost-Only Binding

The backend binds to `127.0.0.1:8080` on the host via Docker port mapping.
It is **not exposed on the local network**. Only processes on the same machine
can reach the API and WebSocket.

### Auth Token

The backend requires authentication for action mutations (POST/PUT/DELETE /api/actions).
On first startup, a random 32-byte auth token is generated and stored in the
Docker volume at `/data/auth_token`.

**Finding the token:**

```bash
# View in startup logs (printed to stdout)
docker compose logs voice-backend | grep "AUTH TOKEN"

# Or read directly from the volume
docker compose exec voice-backend cat /data/auth_token
```

**Setting a custom token:**

```bash
# Write your own token into the data directory
echo "your-secure-token-here" | docker compose exec -T voice-backend tee /data/auth_token > /dev/null
docker compose restart voice-backend
```

**Client authentication:**

The client (`voice_client.py`) automatically fetches the token from the backend
on first run and stores it in `~/.config/voice-module/config.json`. All mutation
requests include the `Authorization: Bearer <token>` header.

- GET endpoints (`/api/status`, `/api/config`, `/api/actions`, `/api/history`) are
  **read-only** and do not require authentication.
- WebSocket connections are accepted without authentication; the WebSocket relays
  status/transcription data only (read-only from untrusted sources).
- POST/PUT/DELETE to `/api/actions` require a valid `Authorization: Bearer <token>` header.

**Token location:**

| Location | Path |
|----------|------|
| Backend (Docker volume) | `/data/auth_token` (inside container) |
| Client (local config) | `~/.config/voice-module/config.json` → `auth_token` key |

### CORS

CORS is restricted to `http://localhost:8080` and `http://127.0.0.1:8080` only.
Cross-origin requests from other origins are rejected.

---

## License

MIT © 2026 [Mathis Naud](https://github.com/mathisnaud)
