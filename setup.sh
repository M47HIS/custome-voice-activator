#!/usr/bin/env bash
# setup.sh — Install dependencies for the Voice Module.
set -euo pipefail

echo "========================================="
echo " Voice Module — Dependency Setup"
echo "========================================="
echo ""

# ── System dependencies ────────────────────────────────────────────────
echo "[1/4] Checking Homebrew packages..."

MISSING_BREW=()

if ! command -v portaudio &>/dev/null; then
    # Check if portaudio lib exists
    if [ ! -f /opt/homebrew/lib/libportaudio.dylib ] && [ ! -f /usr/local/lib/libportaudio.dylib ]; then
        MISSING_BREW+=("portaudio")
    fi
fi

if [ ${#MISSING_BREW[@]} -gt 0 ]; then
    echo "  Installing: ${MISSING_BREW[*]}"
    brew install "${MISSING_BREW[@]}"
else
    echo "  All brew dependencies satisfied."
fi

# ── Python packages ────────────────────────────────────────────────────
echo ""
echo "[2/4] Installing Python packages..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pip3 install -r "$SCRIPT_DIR/requirements.txt"

# ── Client dependencies ────────────────────────────────────────────────
echo ""
echo "[3/4] Installing client packages..."

if [ -f "$SCRIPT_DIR/client/requirements.txt" ]; then
    pip3 install -r "$SCRIPT_DIR/client/requirements.txt"
fi

# ── Voxtral (Apple MLX transcription) ─────────────────────────────────
echo ""
echo "[4/4] Installing Voxtral (Apple MLX)..."
pip3 install mlx-audio 2>/dev/null || echo "  mlx-audio installation skipped (may require macOS 14+)."

# ── Verify ─────────────────────────────────────────────────────────────
echo ""
echo "Verifying installation..."

python3 -c "
import sounddevice as sd
print(f'  sounddevice {sd.__version__}  ✓')
" 2>&1 || echo "  sounddevice ✗"

python3 -c "
import pynput
print(f'  pynput        ✓')
" 2>&1 || echo "  pynput ✗"

python3 -c "
import websocket
print(f'  websocket-client ✓')
" 2>&1 || echo "  websocket-client ✗"

python3 -c "
import mlx_audio
print(f'  mlx-audio    ✓')
" 2>&1 || echo "  mlx-audio ✗ (install with: pip install mlx-audio)"

echo ""
echo "========================================="
echo " Setup complete!"
echo ""
echo " NEXT STEPS:"
echo "  1. Grant Accessibility permission:"
echo "     System Settings → Privacy & Security → Accessibility"
echo "     Add Terminal.app (or your terminal emulator)."
echo ""
echo "  2. Grant Microphone permission:"
echo "     System Settings → Privacy & Security → Microphone"
echo "     The first recording attempt will trigger a permission prompt."
echo ""
echo "  3. Start the module:"
echo "     bash start.sh"
echo ""
echo "  4. Configure hotkey / engine:"
echo "     Edit ~/.config/voice-module/config.json"
echo "========================================="
