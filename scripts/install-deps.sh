#!/usr/bin/env bash
set -euo pipefail

echo "=== Browser Automation: Installing dependencies ==="

# x11vnc for VNC serving
# novnc for web-based VNC client (includes websockify)
sudo apt-get update -qq
sudo apt-get install -y x11vnc novnc

# Ensure Playwright's Chromium has its system deps (libatk, libcups, etc.)
bunx playwright install-deps chromium

# Verify all required binaries
echo ""
echo "=== Verifying binaries ==="
MISSING=0
for cmd in Xvfb x11vnc websockify cloudflared; do
  if command -v "$cmd" &>/dev/null; then
    echo "  ✓ $cmd found: $(command -v "$cmd")"
  else
    echo "  ✗ $cmd NOT FOUND"
    MISSING=1
  fi
done

# Verify Playwright Chromium binary
CHROME_DIR="$HOME/.cache/ms-playwright"
CHROME_BIN=$(find "$CHROME_DIR" -name "chrome" -path "*/chrome-linux64/*" 2>/dev/null | head -1)
if [ -n "$CHROME_BIN" ] && [ -x "$CHROME_BIN" ]; then
  echo "  ✓ Playwright Chromium: $CHROME_BIN"
else
  echo "  ✗ Playwright Chromium not found in $CHROME_DIR"
  echo "    Run: bunx playwright install chromium"
  MISSING=1
fi

# Verify noVNC web files
if [ -f /usr/share/novnc/vnc.html ]; then
  echo "  ✓ noVNC web files: /usr/share/novnc/"
elif [ -f /usr/share/novnc/vnc_lite.html ]; then
  echo "  ✓ noVNC web files: /usr/share/novnc/ (lite only)"
else
  echo "  ✗ noVNC web files not found at /usr/share/novnc/"
  MISSING=1
fi

echo ""
if [ "$MISSING" -eq 0 ]; then
  echo "=== All dependencies verified ✓ ==="
else
  echo "=== Some dependencies missing — see above ==="
  exit 1
fi
