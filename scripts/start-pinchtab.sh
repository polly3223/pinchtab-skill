#!/usr/bin/env bash
set -euo pipefail

PID_DIR="${PINCHTAB_PID_DIR:-/tmp/pinchtab-skill}"
LOG_DIR="${PINCHTAB_LOG_DIR:-$PID_DIR/logs}"
DISPLAY_NUM="${PINCHTAB_DISPLAY_NUM:-99}"
DISPLAY_VAR=":${DISPLAY_NUM}"
PORT="${PINCHTAB_PORT:-${BRIDGE_PORT:-9867}}"
BIND="${PINCHTAB_BIND:-${BRIDGE_BIND:-127.0.0.1}}"
TOKEN="${PINCHTAB_TOKEN:-${BRIDGE_TOKEN:-}}"
if [ "$(uname -s)" = "Linux" ]; then
  DEFAULT_START_XVFB=1
else
  DEFAULT_START_XVFB=0
fi
START_XVFB="${PINCHTAB_START_XVFB:-$DEFAULT_START_XVFB}"
START_TUNNEL="${PINCHTAB_START_TUNNEL:-0}"
SERVER_URL="http://127.0.0.1:$PORT"
HEALTH_URL="$SERVER_URL/health"
DASHBOARD_URL="$SERVER_URL/dashboard"
SERVER_ALREADY_RUNNING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --tunnel)
      START_TUNNEL=1
      shift
      ;;
    --no-xvfb)
      START_XVFB=0
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$PID_DIR" "$LOG_DIR"

sync_browser_env() {
  if [ -n "${CHROME_BINARY:-}" ] && [ -z "${CHROME_BIN:-}" ]; then
    export CHROME_BIN="$CHROME_BINARY"
  fi
  if [ -n "${CHROME_BIN:-}" ] && [ -z "${CHROME_BINARY:-}" ]; then
    export CHROME_BINARY="$CHROME_BIN"
  fi
}

detect_linux_chrome() {
  if [ "$(uname -s)" != "Linux" ]; then
    return
  fi

  if [ -n "${CHROME_BIN:-}" ] || [ -n "${CHROME_BINARY:-}" ]; then
    return
  fi

  local chrome_cmd=""
  for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      chrome_cmd="$(command -v "$candidate")"
      break
    fi
  done

  if [ -z "$chrome_cmd" ]; then
    return
  fi

  if [ "$chrome_cmd" = "/usr/bin/google-chrome-stable" ]; then
    local wrapper="$HOME/.pinchtab/chrome-wrapper.sh"
    mkdir -p "$HOME/.pinchtab"
    cat >"$wrapper" <<'WRAPEOF'
#!/bin/bash
exec /usr/bin/google-chrome-stable --no-sandbox --disable-gpu "$@"
WRAPEOF
    chmod +x "$wrapper"
    export CHROME_BIN="$wrapper"
    export CHROME_BINARY="$wrapper"
    return
  fi

  export CHROME_BIN="$chrome_cmd"
  export CHROME_BINARY="$chrome_cmd"
}

curl_health() {
  local -a cmd
  cmd=(curl -fsS)
  if [ -n "$TOKEN" ]; then
    cmd+=(-H "Authorization: Bearer $TOKEN")
  fi
  cmd+=("$HEALTH_URL")
  "${cmd[@]}" >/dev/null
}

ensure_xvfb() {
  if [ "$START_XVFB" != "1" ]; then
    return
  fi

  if [ -f "$PID_DIR/xvfb.pid" ] && kill -0 "$(cat "$PID_DIR/xvfb.pid")" 2>/dev/null; then
    export DISPLAY="$DISPLAY_VAR"
    return
  fi

  if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "$DISPLAY_VAR" >/dev/null 2>&1; then
    export DISPLAY="$DISPLAY_VAR"
    return
  fi

  if ! command -v Xvfb >/dev/null 2>&1; then
    echo "Xvfb not found. Install it or run with --no-xvfb." >&2
    exit 1
  fi

  nohup Xvfb "$DISPLAY_VAR" -screen 0 1920x1080x24 >"$LOG_DIR/xvfb.log" 2>&1 &
  echo $! >"$PID_DIR/xvfb.pid"
  sleep 1

  if ! kill -0 "$(cat "$PID_DIR/xvfb.pid")" 2>/dev/null; then
    echo "Failed to start Xvfb." >&2
    exit 1
  fi

  export DISPLAY="$DISPLAY_VAR"
}

ensure_pinchtab() {
  if ! command -v pinchtab >/dev/null 2>&1; then
    echo "pinchtab not found. Run scripts/install-deps.sh first." >&2
    exit 1
  fi
}

start_orchestrator() {
  if [ -f "$PID_DIR/pinchtab.pid" ] && kill -0 "$(cat "$PID_DIR/pinchtab.pid")" 2>/dev/null; then
    if curl_health; then
      return
    fi
    rm -f "$PID_DIR/pinchtab.pid"
  fi

  if curl_health; then
    SERVER_ALREADY_RUNNING=1
    return
  fi

  local -a env_cmd
  env_cmd=(env "BRIDGE_PORT=$PORT" "BRIDGE_BIND=$BIND")
  if [ -n "$TOKEN" ]; then
    env_cmd+=("BRIDGE_TOKEN=$TOKEN" "PINCHTAB_TOKEN=$TOKEN")
  fi
  if [ -n "${CHROME_BIN:-}" ]; then
    env_cmd+=("CHROME_BIN=$CHROME_BIN")
  fi
  if [ -n "${CHROME_BINARY:-}" ]; then
    env_cmd+=("CHROME_BINARY=$CHROME_BINARY")
  fi
  if [ -n "${DISPLAY:-}" ]; then
    env_cmd+=("DISPLAY=$DISPLAY")
  fi

  nohup "${env_cmd[@]}" pinchtab server >"$LOG_DIR/pinchtab.log" 2>&1 &
  echo $! >"$PID_DIR/pinchtab.pid"

  for _ in $(seq 1 40); do
    if curl_health; then
      return
    fi
    sleep 1
  done

  echo "PinchTab orchestrator did not become healthy." >&2
  if [ -f "$LOG_DIR/pinchtab.log" ]; then
    tail -n 50 "$LOG_DIR/pinchtab.log" >&2 || true
  fi
  exit 1
}

start_tunnel() {
  if [ "$START_TUNNEL" != "1" ]; then
    return
  fi

  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found; cannot start tunnel." >&2
    exit 1
  fi

  if [ -f "$PID_DIR/cloudflared.pid" ] && kill -0 "$(cat "$PID_DIR/cloudflared.pid")" 2>/dev/null; then
    return
  fi

  nohup cloudflared tunnel --url "$SERVER_URL" --config /dev/null >"$LOG_DIR/cloudflared.log" 2>&1 &
  echo $! >"$PID_DIR/cloudflared.pid"
}

read_tunnel_url() {
  if [ "$START_TUNNEL" != "1" ]; then
    return
  fi

  for _ in $(seq 1 20); do
    local url
    url="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | head -1 || true)"
    if [ -n "$url" ]; then
      echo "$url"
      return
    fi
    sleep 1
  done
}

sync_browser_env
detect_linux_chrome
sync_browser_env
ensure_pinchtab
ensure_xvfb
start_orchestrator
start_tunnel

TUNNEL_URL="$(read_tunnel_url || true)"
PID_LINES=""
if [ -f "$PID_DIR/pinchtab.pid" ]; then
  PID_LINES="    \"pinchtab\": $(cat "$PID_DIR/pinchtab.pid")"
fi
if [ -f "$PID_DIR/xvfb.pid" ]; then
  if [ -n "$PID_LINES" ]; then
    PID_LINES="${PID_LINES},
"
  fi
  PID_LINES="${PID_LINES}    \"xvfb\": $(cat "$PID_DIR/xvfb.pid")"
fi
if [ -f "$PID_DIR/cloudflared.pid" ]; then
  if [ -n "$PID_LINES" ]; then
    PID_LINES="${PID_LINES},
"
  fi
  PID_LINES="${PID_LINES}    \"cloudflared\": $(cat "$PID_DIR/cloudflared.pid")"
fi

cat <<EOF
{
  "serverUrl": "$SERVER_URL",
  "healthUrl": "$HEALTH_URL",
  "dashboardUrl": "$DASHBOARD_URL",
  "bind": "$BIND",
  "port": $PORT,
  "display": "${DISPLAY:-}",
  "tokenConfigured": $([ -n "$TOKEN" ] && echo "true" || echo "false"),
  "chromeBin": "${CHROME_BIN:-${CHROME_BINARY:-}}",
  "serverAlreadyRunning": $([ "$SERVER_ALREADY_RUNNING" = "1" ] && echo "true" || echo "false"),
  "tunnelUrl": "${TUNNEL_URL:-}",
  "pids": {
${PID_LINES}
  }
}
EOF
