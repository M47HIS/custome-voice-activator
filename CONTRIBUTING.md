# Contributing to Voice Module

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

### Prerequisites

- **macOS 13+**
- **Xcode 15+** or Swift toolchain (`swiftlang` via Homebrew)
- **Python 3.11+**
- **OrbStack** or Docker Desktop (optional, for the backend)

### Local Development

```bash
# Clone the repo
git clone https://github.com/mathisnaud/voice-module.git
cd voice-module

# Install Python worker dependencies
pip install -r client/requirements.txt

# Build the Swift menu-bar app
cd macos/VoiceActivator
swift build -c release

# Run it
.build/release/VoiceActivator
```

### Project Structure

```
macos/VoiceActivator/     Swift menu-bar app (primary UI)
  Package.swift
  Sources/VoiceActivator/
    main.swift              Entry point (NSApplication + accessory policy)
    AppDelegate.swift       Bootstrap: supervisor + backend client + settings
    ProcessSupervisor.swift Spawns Python worker, manages hotkey + audio
    StatusBarController.swift Menu-bar icon (NSStatusItem)
    MenuContentView.swift   SwiftUI dropdown menu
    SettingsWindow.swift    Settings UI (hotkey, mode, action, permissions)
    HotkeyManager.swift     Native global hotkey (Carbon RegisterEventHotKey)
    Hotkey.swift            Hotkey parsing (Python-style "cmd+shift+space")
    AudioRecorder.swift     Native mic recording (AVFoundation)
    BackendClient.swift     REST + WebSocket client for optional Docker backend
    SettingsStore.swift     UI-facing settings model
    Models.swift            Wire models (BackendSettings, Action, etc.)
    AppPaths.swift          Centralized filesystem paths
    LogStore.swift          File-backed logger
    AppDiagnostics.swift    Permission checks, Python deps check
    KeyCodes.swift          macOS key code ↔ token mapping
    KeyCaptureView.swift    SwiftUI hotkey capture widget

client/                   Python worker
  voice_client.py         Hotkey + mic + Voxtral + actions (worker mode)
  requirements.txt        Python dependencies

backend/                  Optional Docker coordination layer
  main.py                 FastAPI server (actions, settings, history, WebSocket)
  transcriber.py          Pluggable transcription (faster-whisper or custom)
  config/                 Default action definitions
  Dockerfile
  requirements.txt

docker-compose.yml        Optional backend stack (127.0.0.1:8080)
legacy/                   Archived pre-v1 files (browser UI, standalone script)
```

## Architecture

```
┌────────────────────────┐
│  VoiceActivator.app    │  Swift menu-bar app
│  (native hotkey + mic) │  Settings, process supervisor
└───────────┬────────────┘
            │ spawns + JSON stdin/stdout
            ▼
┌────────────────────────┐
│  voice_client.py       │  Python worker (--worker mode)
│  --worker              │  Transcription + action execution
│                        │
│  - Voxtral (MLX)       │  Apple Neural Engine
│  - Custom command      │  User-provided model runner
│  - paste_focused       │  pbcopy + ⌘V into focused app
└────────────────────────┘
            │ optional WebSocket
            ▼
┌────────────────────────┐
│  Docker backend        │  Action config, history, settings
│  (FastAPI :8080)       │  Not required for core loop
└────────────────────────┘
```

The Swift app handles the native hotkey and microphone recording. It sends
`transcribe_file` JSON commands to the Python worker via stdin. The worker
transcribes the audio and executes the configured action (default: paste into
the focused app).

## Swift Build & Test

```bash
cd macos/VoiceActivator
swift build -c release         # production build
swift build                    # debug build
.build/release/VoiceActivator  # run
```

The app targets **macOS 13+** (`MenuBarExtra`, `Window` scene, `SMAppService`).
Logs are written to `~/Library/Logs/VoiceModule/menu-bar.log`.

## Pull Request Process

1. Fork the repo and create a feature branch from `main`.
2. Update documentation if the change affects user-facing behavior.
3. Ensure `README.md` is up to date.
4. Open a PR with a clear description of what changed and why.

## Code Style

- **Python**: Follow [PEP 8](https://peps.python.org/pep-0008/). Use type hints where practical.
- **Swift**: Follow standard Swift API design guidelines. Async/await for I/O. `@MainActor` for UI state. No force-unwraps (`try!`, `!`).
- Keep files small and focused.

## Commit Messages

Use conventional commit format:

```
feat: add paste_focused action for Superwhisper-style paste
fix: worker crashes when backend is unavailable
docs: rewrite README for native app architecture
refactor: extract custom command engine from Voxtral path
```

## Testing

```bash
# Python syntax check
python3 -m py_compile client/voice_client.py backend/main.py backend/transcriber.py

# Swift build
cd macos/VoiceActivator && swift build -c release

# Manual smoke test
macos/VoiceActivator/.build/release/VoiceActivator
# → menu-bar icon appears, hotkey works, transcription works
```

## Release Checklist

- [ ] All PRs merged with passing checks
- [ ] `README.md` updated
- [ ] Swift app builds clean (`swift build -c release`)
- [ ] Python worker compiles (`python3 -m py_compile client/voice_client.py`)
- [ ] Manual smoke test passed
- [ ] GitHub release drafted

## Questions?

Open an issue or start a discussion.
