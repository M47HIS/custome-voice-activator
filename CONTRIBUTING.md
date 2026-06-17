# Contributing to Voice Module

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

### Prerequisites

- **macOS** (for client + Apple Neural Engine; backend runs in Docker on any host)
- **OrbStack** `brew install orbstack` (or Docker Desktop)
- **Python 3.11+**
- **Swift toolchain** (Xcode 15+ or `swiftlang` Homebrew formula). The menu-bar app builds with `swift build -c release`.
- **Homebrew** (recommended, for `portaudio`)
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
cd ../client
pip install -r requirements.txt
pip install mlx-audio

# Build the menu-bar app
cd ../macos/VoiceActivator
swift build -c release
./Scripts/build_and_run.sh    # builds + launches in one step
```

### Project Structure

```
.
├── backend/                  # Headless FastAPI server (OrbStack/Docker)
│   ├── main.py               # REST + WebSocket handlers (no UI, no transcription)
│   ├── config/               # Default action definitions
│   ├── Dockerfile
│   └── requirements.txt
├── client/                   # macOS native transcription client
│   ├── voice_client.py       # Hotkey + mic + Voxtral + actions (Python)
│   └── requirements.txt
├── macos/VoiceActivator/     # Swift menu-bar app (primary UI)
│   ├── Package.swift
│   ├── Sources/VoiceActivator/
│   │   ├── main.swift
│   │   ├── AppDelegate.swift
│   │   ├── StatusBarController.swift
│   │   ├── MenuContentView.swift
│   │   ├── SettingsWindow.swift
│   │   ├── KeyCaptureView.swift
│   │   ├── KeyCodes.swift
│   │   ├── Hotkey.swift
│   │   ├── Models.swift
│   │   ├── BackendClient.swift
│   │   ├── ProcessSupervisor.swift
│   │   ├── SettingsStore.swift
│   │   ├── AppPaths.swift
│   │   └── LogStore.swift
│   └── Scripts/build_and_run.sh
├── docker-compose.yml        # Local backend stack (port 127.0.0.1:8080)
├── voice_module.py           # Legacy standalone (faster-whisper, no Docker)
├── requirements.txt          # Legacy standalone dependencies
├── start.sh                  # Legacy CLI launcher (use the menu-bar app instead)
├── setup.sh
```

## How It Works

```
┌────────────────────────┐   WebSocket/REST    ┌──────────────────────┐
│  macOS menu-bar app     │ ◄────────────────► │  Backend (OrbStack)  │
│  (Swift, primary UI)    │  settings, status  │                      │
│                        │                    │  FastAPI :8080        │
│  - ProcessSupervisor   │                    │  Actions + History    │
│  - BackendClient       │                    │  No UI (headless)     │
│  - Settings window     │                    │                      │
└────────────┬───────────┘                    └──────────────────────┘
             │ spawns
             ▼
┌────────────────────────┐
│  Python client         │   WebSocket        ┌──────────────────────┐
│  voice_client.py       │ ◄────────────────► │  Backend              │
│                        │                    │                      │
│  - pynput hotkey        │                    │  Status relay         │
│  - sounddevice mic     │                    │  Transcription log    │
│  - Voxtral (Apple MLX) │                    │  Action config source │
│  - Action runner        │                    │                      │
└────────────────────────┘                    └──────────────────────┘
```

**Voxtral** transcribes audio on the client using Apple Neural Engine.
The backend is a lightweight coordination layer — no model loading,
no audio processing, no ffmpeg required.

WebSocket protocol:
- Client sends: `{"type":"hello","role":"client"}`, `{"type":"status","state":"listening|transcribing|idle"}`, `{"type":"transcription","text":"...","is_final":true}`
- Server broadcasts status and transcription to all UI observers
- No binary audio frames

## Swift build & test

```bash
cd macos/VoiceActivator
swift build -c release         # builds .build/release/VoiceActivator
swift build                    # debug build
./Scripts/build_and_run.sh     # build + launch
```

The Swift app targets **macOS 13+** (`MenuBarExtra`, `Window` scene). The
log file is written to `~/Library/Logs/VoiceModule/menu-bar.log`.

## Pull Request Process

1. Fork the repo and create a feature branch from `main`.
2. Write or update tests for your changes.
3. Update documentation if your change affects user-facing behavior.
4. Ensure `README.md` is up to date with any new features.
5. Open a PR with a clear description of what changed and why.

## Code Style

- **Python**: Follow [PEP 8](https://peps.python.org/pep-0008/). Use type hints where practical.
- **Swift**: Follow standard Swift API design guidelines. Async/await for I/O. `@MainActor` for UI state. No force-unwraps (`try!`, `!`).
- **No inline `onclick`** in any SwiftUI view — use `Button(action:)` with closures.
- Keep files small and focused. No file should exceed ~600 lines without good reason.

## Commit Messages

Use conventional commit format:

```
feat: add Voxtral local transcription
fix: hotkey listener crashes after Mac sleep
docs: update README with menu-bar app setup
refactor: extract VoxtralTranscriber from voice_client.py
```

## Testing

```bash
# Python syntax check
PYTHONPYCACHEPREFIX=/private/tmp/voice-module-pycache \
  python3 -m py_compile voice_module.py client/voice_client.py backend/main.py

# Swift build
cd macos/VoiceActivator
swift build -c release

# Manual smoke test
docker compose config           # verify 127.0.0.1:8080 binding
docker compose up -d
curl http://localhost:8080/api/status
cd client && python3 voice_client.py --list-devices
```

## Release Checklist

- [ ] All PRs merged with passing checks
- [ ] `README.md` updated with any new features
- [ ] Version bumped in relevant files
- [ ] Docker image built and tested
- [ ] Swift menu-bar app builds clean (`swift build -c release`)
- [ ] GitHub release drafted with changelog

## Questions?

Open an issue or start a discussion. We're happy to help!
