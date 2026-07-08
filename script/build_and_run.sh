#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-build}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macos/VoiceActivator"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
APP_URL="http://127.0.0.1:8080"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

compose() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

ensure_docker() {
    command -v docker >/dev/null 2>&1 || fail "docker was not found on PATH."
    docker info >/dev/null 2>&1 || fail "Docker/OrbStack is not running."
}

build_swift() {
    echo "==> Building VoiceActivator.app..."
    (cd "$SWIFT_DIR" && swift build -c release) || fail "Swift build failed."
    echo "[PASS] Swift build"
}

verify() {
    local failures=0
    echo "==> Verifying Voice Module"

    # Swift binary exists
    if [ -f "$SWIFT_DIR/.build/release/VoiceActivator" ]; then
        echo "[PASS] VoiceActivator binary"
    else
        echo "[FAIL] VoiceActivator binary not found"
        failures=$((failures + 1))
    fi

    # Python worker compiles
    if PYTHONPYCACHEPREFIX=/private/tmp/voice-module-pycache \
        python3 -m py_compile "$ROOT_DIR/client/voice_client.py" 2>/dev/null; then
        echo "[PASS] Python worker compiles"
    else
        echo "[FAIL] Python worker does not compile"
        failures=$((failures + 1))
    fi

    # Backend compiles (if present)
    if [ -f "$ROOT_DIR/backend/main.py" ]; then
        if PYTHONPYCACHEPREFIX=/private/tmp/voice-module-pycache \
            python3 -m py_compile "$ROOT_DIR/backend/main.py" 2>/dev/null; then
            echo "[PASS] Backend compiles"
        else
            echo "[FAIL] Backend does not compile"
            failures=$((failures + 1))
        fi
    fi

    # Optional: Docker backend (if running)
    if curl -fsS "$APP_URL/api/status" 2>/dev/null | grep -q '"state"'; then
        echo "[PASS] Docker backend (optional)"
    else
        echo "[SKIP] Docker backend not running (optional)"
    fi

    if [ "$failures" -gt 0 ]; then
        fail "$failures verification check(s) failed."
    fi
    echo "==> Verification passed."
}

case "$MODE" in
    build)
        build_swift
        echo "VoiceActivator built: $SWIFT_DIR/.build/release/VoiceActivator"
        ;;
    run)
        build_swift
        echo "Starting VoiceActivator..."
        "$SWIFT_DIR/.build/release/VoiceActivator" &
        echo "VoiceActivator running (PID=$!)."
        ;;
    --verify|verify)
        build_swift
        verify
        ;;
    --backend|backend)
        ensure_docker
        compose up -d --build
        echo "Docker backend starting: $APP_URL"
        ;;
    --stop|stop)
        pkill -f VoiceActivator 2>/dev/null || true
        if command -v docker >/dev/null 2>&1; then
            compose down 2>/dev/null || true
        fi
        echo "Stopped."
        ;;
    *)
        echo "usage: $0 [build|run|--verify|--backend|--stop]" >&2
        exit 2
        ;;
esac
