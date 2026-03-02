#!/usr/bin/env bash
# Launch full browser automation stack: Xvfb + Chromium + x11vnc + websockify/noVNC + cloudflared
# Usage: launch-browser.sh [target-url]
# Outputs JSON with connection info on success
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configuration
DISPLAY_NUM=99
DISPLAY_VAR=":${DISPLAY_NUM}"
SCREEN_RES="1280x1024x24"
VNC_PORT=5900
NOVNC_PORT=6080
CDP_PORT=9222
PID_DIR="/tmp/browser-automation"
LOG_DIR="/tmp/browser-automation/logs"
NOVNC_DIR="/usr/share/novnc"

# Find Playwright's bundled Chromium
CHROME_DIR="$HOME/.cache/ms-playwright"
CHROME_BIN=$(find "$CHROME_DIR" -name "chrome" -path "*/chrome-linux64/*" 2>/dev/null | head -1)

if [ -z "$CHROME_BIN" ] || [ ! -x "$CHROME_BIN" ]; then
  echo "ERROR: Playwright Chromium not found. Run install-deps.sh first." >&2
  exit 1
fi

# Accept optional target URL
TARGET_URL="${1:-about:blank}"

# Clean any stale session
bash "$SCRIPT_DIR/stop-browser.sh" 2>/dev/null || true

mkdir -p "$PID_DIR" "$LOG_DIR"

# --- 1. Start Xvfb ---
echo "Starting Xvfb on display $DISPLAY_VAR..." >&2
Xvfb "$DISPLAY_VAR" -screen 0 "$SCREEN_RES" -ac +extension GLX +render -noreset \
  > "$LOG_DIR/xvfb.log" 2>&1 &
echo $! > "$PID_DIR/xvfb.pid"
sleep 1

if ! kill -0 "$(cat "$PID_DIR/xvfb.pid")" 2>/dev/null; then
  echo "ERROR: Xvfb failed to start" >&2
  cat "$LOG_DIR/xvfb.log" >&2
  exit 1
fi
echo "  Xvfb started (PID $(cat "$PID_DIR/xvfb.pid"))" >&2

# --- 2. Launch Chromium with CDP ---
echo "Starting Chromium with CDP on port $CDP_PORT..." >&2
DISPLAY="$DISPLAY_VAR" "$CHROME_BIN" \
  --no-first-run \
  --no-default-browser-check \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  --disable-dev-shm-usage \
  --no-sandbox \
  --remote-debugging-port="$CDP_PORT" \
  --remote-debugging-address=127.0.0.1 \
  --window-size=1280,1024 \
  --start-maximized \
  --user-data-dir="/tmp/browser-automation/chrome-profile" \
  "$TARGET_URL" \
  > "$LOG_DIR/chrome.log" 2>&1 &
echo $! > "$PID_DIR/chrome.pid"
sleep 2

if ! kill -0 "$(cat "$PID_DIR/chrome.pid")" 2>/dev/null; then
  echo "ERROR: Chromium failed to start" >&2
  cat "$LOG_DIR/chrome.log" >&2
  bash "$SCRIPT_DIR/stop-browser.sh" 2>/dev/null || true
  exit 1
fi
echo "  Chromium started (PID $(cat "$PID_DIR/chrome.pid"))" >&2

# Wait for CDP endpoint
for i in $(seq 1 15); do
  if curl -s "http://127.0.0.1:$CDP_PORT/json/version" > /dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 15 ]; then
    echo "ERROR: CDP endpoint not reachable on port $CDP_PORT" >&2
    bash "$SCRIPT_DIR/stop-browser.sh" 2>/dev/null || true
    exit 1
  fi
  sleep 0.5
done
echo "  CDP endpoint ready" >&2

# --- 3. Start x11vnc ---
echo "Starting x11vnc on port $VNC_PORT..." >&2
x11vnc -display "$DISPLAY_VAR" -rfbport "$VNC_PORT" -nopw -shared -forever \
  -xkb -ncache 10 -ncache_cr \
  > "$LOG_DIR/x11vnc.log" 2>&1 &
echo $! > "$PID_DIR/x11vnc.pid"
sleep 1

if ! kill -0 "$(cat "$PID_DIR/x11vnc.pid")" 2>/dev/null; then
  echo "ERROR: x11vnc failed to start" >&2
  cat "$LOG_DIR/x11vnc.log" >&2
  bash "$SCRIPT_DIR/stop-browser.sh" 2>/dev/null || true
  exit 1
fi
echo "  x11vnc started (PID $(cat "$PID_DIR/x11vnc.pid"))" >&2

# --- 4. Start websockify with noVNC ---
echo "Starting websockify (noVNC) on port $NOVNC_PORT..." >&2
websockify --web "$NOVNC_DIR" "$NOVNC_PORT" "localhost:$VNC_PORT" \
  > "$LOG_DIR/websockify.log" 2>&1 &
echo $! > "$PID_DIR/websockify.pid"
sleep 1

# Verify noVNC is serving
for i in $(seq 1 10); do
  if curl -s "http://localhost:$NOVNC_PORT/vnc.html" > /dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 10 ]; then
    echo "ERROR: noVNC not responding on port $NOVNC_PORT" >&2
    bash "$SCRIPT_DIR/stop-browser.sh" 2>/dev/null || true
    exit 1
  fi
  sleep 0.5
done
echo "  noVNC ready on port $NOVNC_PORT" >&2

# --- 5. Start cloudflared quick tunnel ---
echo "Starting cloudflared quick tunnel..." >&2
cloudflared tunnel --url "http://localhost:$NOVNC_PORT" --config /dev/null \
  > "$LOG_DIR/cloudflared.log" 2>&1 &
echo $! > "$PID_DIR/cloudflared.pid"

# Wait for tunnel URL (up to 30s)
TUNNEL_URL=""
for i in $(seq 1 30); do
  TUNNEL_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | head -1 || true)
  if [ -n "$TUNNEL_URL" ]; then
    break
  fi
  sleep 1
done

if [ -z "$TUNNEL_URL" ]; then
  echo "ERROR: Could not get cloudflared tunnel URL after 30s" >&2
  cat "$LOG_DIR/cloudflared.log" >&2
  bash "$SCRIPT_DIR/stop-browser.sh" 2>/dev/null || true
  exit 1
fi
echo "  Tunnel ready: $TUNNEL_URL" >&2

# Construct noVNC URL with auto-connect
NOVNC_URL="${TUNNEL_URL}/vnc.html?autoconnect=true&resize=remote"

# --- Output JSON (only this goes to stdout) ---
cat <<EOJSON
{
  "novnc_url": "$NOVNC_URL",
  "tunnel_url": "$TUNNEL_URL",
  "cdp_url": "http://127.0.0.1:$CDP_PORT",
  "display": "$DISPLAY_VAR",
  "target_url": "$TARGET_URL",
  "pids": {
    "xvfb": $(cat "$PID_DIR/xvfb.pid"),
    "chrome": $(cat "$PID_DIR/chrome.pid"),
    "x11vnc": $(cat "$PID_DIR/x11vnc.pid"),
    "websockify": $(cat "$PID_DIR/websockify.pid"),
    "cloudflared": $(cat "$PID_DIR/cloudflared.pid")
  }
}
EOJSON
