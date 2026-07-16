# VoiceActivator

VoiceActivator is a small macOS menu-bar app for local voice-to-text. Hold a
customizable shortcut, speak, release, and the transcript is copied to your
clipboard.

The default transcription path runs locally. Audio only leaves your Mac if you
explicitly configure a custom command or integration that sends it elsewhere.

## What it does

- Native menu-bar app with a compact status popover
- Customizable global keyboard shortcut
- Hold-to-talk and start/stop recording modes
- Local Voxtral transcription through Apple MLX
- Clipboard-only output, with no simulated paste or Accessibility permission
- Short-lived recording, success, and error overlays
- Optional custom transcription command
- Optional authenticated local Docker backend for status coordination

## Requirements

- macOS 13 or later on Apple silicon
- Xcode 15 or a compatible Swift toolchain
- Python 3.11 or later
- Microphone permission for `VoiceActivator.app`
- Several gigabytes of free space for the local model on first use

## Install

Clone the repository, then run:

```bash
./script/build_and_run.sh --install
open /Applications/VoiceActivator.app
```

The installer builds the Swift app, creates a private Python environment under
`~/Library/Application Support/VoiceModule/`, installs the worker dependencies,
and copies the signed app to `/Applications`.

The first transcription downloads the local model. After that, click the
menu-bar waveform icon to open Settings or check status.

## Shortcut and output

The default shortcut is `⌘⇧Space`:

1. Hold the shortcut.
2. Speak.
3. Release it.
4. Paste the copied transcript wherever you want.

To change the shortcut, click the menu-bar icon, open Settings, click the
shortcut field, and type a new combination. Saving re-registers it immediately.

VoiceActivator intentionally copies to the clipboard and does not synthesize a
paste keystroke.

## Configuration

User configuration lives at `~/.config/voice-module/config.json`:

```json
{
  "hotkey": "cmd+shift+space",
  "mode": "hold",
  "action": "clipboard",
  "transcribe_command": "",
  "language": "en",
  "engine": "voxtral"
}
```

Existing `paste_focused` configurations are migrated to `clipboard` when the
worker starts.

### Custom transcription command

Set `transcribe_command` to a command that accepts an audio file and prints the
transcript to standard output. `{file}` is replaced with the recording path:

```json
{
  "transcribe_command": "whisper {file} --model base.en --output_format txt"
}
```

You can also set `TRANSCRIBE_COMMAND` in the app's launch environment.

## Development

```bash
# Swift tests
swift test --package-path macos/VoiceActivator

# Python syntax checks
PYTHONPYCACHEPREFIX=/private/tmp/voice-module-pycache \
  python3 -m py_compile client/voice_client.py backend/main.py backend/transcriber.py

# Full local verification
./script/build_and_run.sh --verify
```

The main components are:

```text
macos/VoiceActivator/   Native menu-bar app and settings UI
client/voice_client.py  Local transcription worker
backend/                Optional local FastAPI backend
legacy/                 Archived browser-first prototype
script/                 Build, install, and verification commands
```

## Optional backend

The app does not require Docker. For local backend experiments only:

```bash
export VOICE_MODULE_AUTH_TOKEN="$(openssl rand -hex 32)"
docker compose up -d
```

Use the same token in the Python client's local `auth_token` setting or its
`VOICE_MODULE_AUTH_TOKEN` environment variable. The backend never returns the
token from an API and accepts sensitive REST/WebSocket traffic only from an
authenticated loopback client. The generated token is stored in the Docker
volume at `/data/auth_token` with user-only permissions.

Only the clipboard action is accepted from backend configuration. Terminal,
AppleScript, and webhook actions are intentionally outside the remote backend
trust boundary.

The service binds to `127.0.0.1:8080`. Do not expose it to a public network.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidance. Please report
security issues according to [SECURITY.md](SECURITY.md), not in a public issue.

## License

MIT. See [LICENSE](LICENSE).
