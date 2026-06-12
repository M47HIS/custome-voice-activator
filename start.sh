#!/usr/bin/env bash
# start.sh — Launch the Voice Module (Docker backend + native client).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo " Voice Module — Start"
echo "========================================="
echo ""

# ── Step 1: Start Docker backend ────────────────────────────────────────────
echo "[1/2] Starting backend (OrbStack/Docker)..."

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is not installed or not in PATH."
    echo "Install OrbStack:  brew install orbstack"
    echo "Or Docker Desktop: https://docker.com"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running."
    echo "Start OrbStack (or Docker Desktop) and try again."
    exit 1
fi

# Start the backend if not already running
if docker ps --format '{{.Names}}' | grep -q "voice-module-backend"; then
    echo "  Backend already running."
else
    echo "  Building and starting backend..."
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --build

    echo "  Waiting for backend to be ready..."
    for i in $(seq 1 15); do
        if curl -s http://localhost:8080/api/status >/dev/null 2>&1; then
            echo "  Backend is ready!"
            break
        fi
        sleep 1
        echo "  ... waiting ($i/15)"
    done
fi

echo ""

# ── Step 2: Start native client ─────────────────────────────────────────────
echo "[2/2] Starting macOS client..."

CLIENT_SCRIPT="$SCRIPT_DIR/client/voice_client.py"
LEGACY_SCRIPT="$SCRIPT_DIR/voice_module.py"

# Check if the new client exists, fall back to legacy
if [ -f "$CLIENT_SCRIPT" ]; then
    PYTHON_SCRIPT="$CLIENT_SCRIPT"
    echo "  Using Voxtral-powered client."
else
    PYTHON_SCRIPT="$LEGACY_SCRIPT"
    echo "  Using legacy standalone client (no Docker)."
fi

# Check if already running
if pgrep -f "voice_client.py" >/dev/null 2>&1 || pgrep -f "voice_module.py" >/dev/null 2>&1; then
    echo "  Client already running."
    echo "  To stop: pkill -f voice_client.py; pkill -f voice_module.py"
    echo ""
else
    # Create log directory
    LOG_DIR="$HOME/.local/log/voice-module"
    mkdir -p "$LOG_DIR"
    LOGFILE="$LOG_DIR/voice-module-$(date +%Y%m%d).log"

    echo "  Starting client..."
    echo "  Hotkey: Cmd+Shift+Space (hold to record, release to transcribe)"
    echo "  Logs:   $LOGFILE"
    echo ""

    nohup python3 "$PYTHON_SCRIPT" "$@" >> "$LOGFILE" 2>&1 &
    PID=$!
    echo "  Client started (PID: $PID)."
fi

echo ""
echo "========================================="
echo " Ready!"
echo ""
echo " Web UI:  http://localhost:8080"
echo " Hotkey:  Cmd+Shift+Space"
echo " Stop:    pkill -f voice_client.py; pkill -f voice_module.py"
echo " Logs:    tail -f ~/.local/log/voice-module/voice-module-\$(date +%Y%m%d).log"
echo "========================================="
