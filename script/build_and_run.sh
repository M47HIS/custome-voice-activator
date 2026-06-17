#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VoiceActivator"
BUNDLE_ID="com.mathisnaud.VoiceActivator"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/VoiceActivator"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
CLIENT_PID_FILE="$HOME/Library/Application Support/VoiceModule/voice_client.pid"
LOG_FILE="$HOME/Library/Logs/VoiceModule/menu-bar.log"

# === Helpers ===
fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# === Verification checks ===
check_process_count() {
    local count
    count=$(pgrep -x "$APP_NAME" 2>/dev/null | wc -l | tr -d ' ') || true
    count="${count:-0}"
    if [ "$count" = "1" ]; then
        echo "[PASS] Process count ($count)"
        return 0
    else
        echo "[FAIL] Process count: expected 1, got $count"
        return 1
    fi
}

check_backend_healthy() {
    local i resp
    for i in $(seq 1 30); do
        resp=""
        resp=$(curl -sf http://localhost:8080/api/status 2>/dev/null) || true
        if [ -n "$resp" ] && echo "$resp" | grep -q '"state"'; then
            echo "[PASS] Backend healthy"
            return 0
        fi
        sleep 2
    done
    echo "[FAIL] Backend healthy (no valid /api/status response within 60s)"
    return 1
}

check_worker_process() {
    local count
    count=$(pgrep -f "voice_client.py.*--worker" 2>/dev/null | wc -l | tr -d ' ') || true
    count="${count:-0}"
    if [ "$count" = "1" ]; then
        echo "[PASS] Worker process ($count)"
        return 0
    else
        echo "[FAIL] Worker process: expected 1, got $count"
        return 1
    fi
}

check_pid_liveness() {
    if [ ! -f "$CLIENT_PID_FILE" ]; then
        echo "[FAIL] PID file liveness (file missing: $CLIENT_PID_FILE)"
        return 1
    fi
    local pid
    pid=$(tr -d '[:space:]' < "$CLIENT_PID_FILE")
    if [ -z "$pid" ]; then
        echo "[FAIL] PID file liveness (file empty: $CLIENT_PID_FILE)"
        return 1
    fi
    if kill -0 "$pid" 2>/dev/null; then
        echo "[PASS] PID file liveness (pid=$pid)"
        return 0
    else
        echo "[FAIL] PID file liveness (pid=$pid not alive)"
        return 1
    fi
}

check_hotkey_log() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "[FAIL] Hotkey in log (log file missing: $LOG_FILE)"
        return 1
    fi
    if grep -qF "Registered native hotkey:" "$LOG_FILE" 2>/dev/null; then
        echo "[PASS] Hotkey in log"
        return 0
    else
        echo "[FAIL] Hotkey in log (string not found: \"Registered native hotkey:\")"
        return 1
    fi
}

check_worker_ready_log() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "[FAIL] Worker ready in log (log file missing: $LOG_FILE)"
        return 1
    fi
    if grep -qF "Worker ready." "$LOG_FILE" 2>/dev/null; then
        echo "[PASS] Worker ready in log"
        return 0
    else
        echo "[FAIL] Worker ready in log (string not found: \"Worker ready.\")"
        return 1
    fi
}

run_checks() {
    local failures=0
    echo ""
    echo "=== Running 6 verification checks ==="
    echo ""

    if ! check_process_count;   then failures=$((failures + 1)); fi
    if ! check_backend_healthy;  then failures=$((failures + 1)); fi
    if ! check_worker_process;   then failures=$((failures + 1)); fi
    if ! check_pid_liveness;     then failures=$((failures + 1)); fi
    if ! check_hotkey_log;       then failures=$((failures + 1)); fi
    if ! check_worker_ready_log; then failures=$((failures + 1)); fi

    echo ""
    if [ "$failures" -gt 0 ]; then
        echo "=== Verification FAILED: $failures check(s) failed ==="
        exit 1
    fi
    echo "=== All 6 checks PASSED ==="
}

# === --verify-installed: skip build, launch installed app, check ===
if [ "$MODE" = "--verify-installed" ] || [ "$MODE" = "verify-installed" ]; then
    INSTALLED_APP="/Applications/$APP_NAME.app"
    if [ ! -d "$INSTALLED_APP" ]; then
        fail "/Applications/VoiceActivator.app does not exist. Run --install first."
    fi
    echo "==> Launching installed $INSTALLED_APP..."
    VOICE_MODULE_REPO="$ROOT_DIR" /usr/bin/open -n "$INSTALLED_APP"
    sleep 8
    run_checks
    exit 0
fi

# === Build flow (all other modes) ===
usage() {
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-installed|--install]" >&2
}

if ! command -v swift >/dev/null 2>&1; then
    echo "ERROR: swift toolchain not found. Install Xcode or the Swift toolchain." >&2
    exit 1
fi

echo "==> Stopping existing $APP_NAME process if present..."
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
if [ -f "$CLIENT_PID_FILE" ]; then
    CLIENT_PID="$(tr -d '[:space:]' < "$CLIENT_PID_FILE")"
    if [ -n "$CLIENT_PID" ] && kill -0 "$CLIENT_PID" >/dev/null 2>&1; then
        echo "==> Stopping existing voice client (pid=$CLIENT_PID)..."
        kill "$CLIENT_PID" >/dev/null 2>&1 || true
        sleep 1
        if kill -0 "$CLIENT_PID" >/dev/null 2>&1; then
            kill -9 "$CLIENT_PID" >/dev/null 2>&1 || true
        fi
    fi
    rm -f "$CLIENT_PID_FILE"
fi

echo "==> Building $APP_NAME (release)..."
BUILD_DIR="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
swift build --package-path "$PACKAGE_DIR" -c release

if [ ! -x "$BUILD_BINARY" ]; then
    echo "ERROR: build did not produce $BUILD_BINARY" >&2
    exit 1
fi

echo "==> Staging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_SYSTEM_VERSION</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceActivator needs microphone access to capture audio for local voice transcription.</string>
</dict>
</plist>
PLIST

open_app() {
    VOICE_MODULE_REPO="$ROOT_DIR" /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        VOICE_MODULE_REPO="$ROOT_DIR" lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 8
        run_checks
        ;;
    --install|install)
        INSTALL_TARGET="/Applications/$APP_NAME.app"
        echo "==> Installing $APP_BUNDLE to $INSTALL_TARGET..."
        rm -rf "$INSTALL_TARGET"
        cp -R "$APP_BUNDLE" "$INSTALL_TARGET"
        echo "==> Ad-hoc signing $INSTALL_TARGET..."
        codesign --force --deep --sign - "$INSTALL_TARGET" || {
            echo "ERROR: codesign failed. Check command-line tools." >&2
            exit 1
        }
        echo "Installed and signed $INSTALL_TARGET"
        ;;
    *)
        usage
        exit 2
        ;;
esac

echo "VoiceActivator launched from $APP_BUNDLE" || true
