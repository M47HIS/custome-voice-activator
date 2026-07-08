# Voice Module

macOS menu-bar app for local voice-to-text. Press a hotkey, speak, release —
the transcript is pasted into whatever app you're using. Like Superwhisper, but
open source and fully local.

No audio leaves your machine. No cloud APIs.

## How It Works

```
┌─────────────────────────┐
│  VoiceActivator.app     │  Swift menu-bar icon
│  (native hotkey + mic)  │  Settings window, process supervisor
└───────────┬─────────────┘
            │ spawns
            ▼
┌─────────────────────────┐
│  voice_client.py        │  Python worker
│  --worker mode          │  Transcription + action execution
│                         │
│  Engine priority:       │
│  1. TRANSCRIBE_COMMAND  │  Your own model runner
│  2. Voxtral (MLX)       │  Apple Neural Engine
└─────────────────────────┘
```

The Swift app owns the hotkey and microphone. The Python worker receives
recorded audio via JSON commands, transcribes it, and executes the configured
action (default: paste into the focused app).

An optional Docker backend provides action configuration and transcription
history, but the app works without it.

## Quick Start

```bash
# Build the Swift app
cd macos/VoiceActivator
swift build -c release

# Run it
.build/release/VoiceActivator
```

The app appears in your menu bar. Click the icon to see status, open settings,
or quit.

### Prerequisites

- **macOS 13+**
- **Python 3.11+** with these packages:

```bash
pip install -r client/requirements.txt
```

- **Microphone permission** for VoiceActivator.app (prompted on first use)
- **Accessibility permission** for paste-into-focused-app (prompted on first use)

## Hotkey

Default: **⌘⇧Space** (hold to record, release to transcribe).

Change it in the Settings window (click the menu-bar icon → Settings…).

## Transcription Engines

The worker picks the first available engine:

| Priority | Engine | How to configure |
|----------|--------|-----------------|
| 1 | Custom command | Set `transcribe_command` in `~/.config/voice-module/config.json` or `TRANSCRIBE_COMMAND` env var |
| 2 | Voxtral | Automatic if `mlx-audio` is installed (default) |

### Custom command

Your command receives the audio file path and must print the transcript to
stdout. Use `{file}` as a placeholder:

```json
{
  "transcribe_command": "python3 /path/to/my_model.py {file}"
}
```

Or via environment variable:

```bash
TRANSCRIBE_COMMAND="whisper {file} --model base.en --output_format txt" \
  .build/release/VoiceActivator
```

### Voxtral (default)

Voxtral Mini runs on Apple Neural Engine via MLX. First transcription downloads
the model (~2 GB). Install with:

```bash
pip install mlx-audio
```

## Actions

After transcription, the worker executes the configured action:

| Action | What it does |
|--------|-------------|
| `paste_focused` | Copy to clipboard + simulate ⌘V into the focused app (default) |
| `clipboard` | Copy to clipboard only |
| `opencode` | Open Terminal with opencode and paste |
| `shell` | Run a shell command with the transcript |

Change the action in Settings.

## Optional Docker Backend

The Docker backend provides action configuration, transcription history, and
settings sync. It is **not required** for the core record → transcribe → paste
loop.

```bash
docker compose up -d
```

The backend binds to `127.0.0.1:8080`. Do not expose it to your network.

## Project Structure

```
macos/VoiceActivator/     Swift menu-bar app (primary UI)
client/voice_client.py    Python worker (hotkey, transcription, actions)
backend/                  Optional Docker coordination layer
  main.py                 FastAPI server (actions, settings, history)
  transcriber.py          Pluggable transcription (for Docker backend)
  config/                 Default action definitions
docker-compose.yml        Optional backend stack
legacy/                   Archived pre-v1 files (browser UI, standalone script)
```

## Configuration

User config lives at `~/.config/voice-module/config.json`:

```json
{
  "hotkey": "cmd+shift+space",
  "mode": "hold",
  "action": "paste_focused",
  "transcribe_command": "",
  "language": "en",
  "engine": "voxtral"
}
```

## Development

```bash
# Swift build
cd macos/VoiceActivator && swift build -c release

# Python syntax check
python3 -m py_compile client/voice_client.py backend/main.py backend/transcriber.py

# Run the app
macos/VoiceActivator/.build/release/VoiceActivator

# Optional: start Docker backend
docker compose up -d
```

## License

MIT. See [LICENSE](LICENSE).
