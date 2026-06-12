# Contributing to Voice Module

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

### Prerequisites

- macOS (for client development + Apple Neural Engine)
- OrbStack `brew install orbstack` (or Docker Desktop)
- Python 3.11+
- Homebrew (recommended, for `portaudio`)
- `mlx-audio` (Voxtral transcription engine)

### Local Development

```bash
# Clone the repo
git clone https://github.com/mathisnaud/voice-module.git
cd voice-module

# Start the backend in OrbStack/Docker
docker compose up -d

# Or run the backend locally for faster iteration
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8080

# Install client dependencies
cd client
pip install -r requirements.txt
pip install mlx-audio

# Run the client
python3 voice_client.py --debug
```

### Project Structure

```
.
├── backend/           # Lightweight FastAPI server (OrbStack/Docker)
│   ├── main.py        # REST + WebSocket handlers (no transcription)
│   ├── static/        # Web UI (HTML/CSS/JS)
│   ├── config/        # Default action definitions
│   ├── Dockerfile
│   └── requirements.txt
├── client/            # macOS native client
│   ├── voice_client.py  # Hotkey + mic + Voxtral + actions
│   └── requirements.txt
├── docker-compose.yml
├── voice_module.py    # Legacy standalone (faster-whisper, no Docker needed)
├── requirements.txt   # Legacy standalone dependencies
├── start.sh
├── setup.sh
```

## How It Works

```
┌────────────────────────┐        WebSocket          ┌──────────────────────┐
│   macOS Client          │ ◄───────────────────────► │   Backend (OrbStack)  │
│                         │   status/transcription    │                      │
│  - pynput hotkey        │                           │  - FastAPI            │
│  - sounddevice mic      │                           │  - Actions + History  │
│  - Voxtral (Apple MLX)  │                           │  - Web UI dashboard   │
│  - Action runner        │                           │                      │
└────────────────────────┘                           └──────────────────────┘
```

**Voxtral** transcribes audio on the client using Apple Neural Engine.
The backend is a lightweight coordination layer — no model loading,
no audio processing, no ffmpeg required.

WebSocket protocol:
- Client sends: `{"type":"hello","role":"client"}`, `{"type":"status","state":"listening|transcribing|idle"}`, `{"type":"transcription","text":"...","is_final":true}`
- Server broadcasts status and transcription to all UI observers
- No binary audio frames

## Pull Request Process

1. Fork the repo and create a feature branch from `main`.
2. Write or update tests for your changes.
3. Update documentation if your change affects user-facing behavior.
4. Ensure `README.md` is up to date with any new features.
5. Open a PR with a clear description of what changed and why.

## Code Style

- Python: Follow [PEP 8](https://peps.python.org/pep-0008/). Use type hints where practical.
- JavaScript: Modern ES6+. No framework dependency — vanilla JS only for the web UI.
- CSS: OKLCH color space for theming. Custom properties for tokens. Prefers-reduced-motion support.
- Keep files small and focused. No file should exceed ~600 lines without good reason.

## Commit Messages

Use conventional commit format:

```
feat: add Voxtral local transcription
fix: hotkey listener crashes after Mac sleep
docs: update README with OrbStack setup
refactor: extract VoxtralTranscriber from voice_client.py
```

## Testing

```bash
# Run backend unit tests
cd backend && python -m pytest

# Test the WebSocket endpoint manually
curl http://localhost:8080/api/status

# Test client with debug output
cd client && python3 voice_client.py --debug --list-devices
```

## Release Checklist

- [ ] All PRs merged with passing checks
- [ ] `README.md` updated with any new features
- [ ] Version bumped in relevant files
- [ ] Docker image built and tested
- [ ] GitHub release drafted with changelog

## Questions?

Open an issue or start a discussion. We're happy to help!
