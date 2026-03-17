#!/usr/bin/env bash
set -euo pipefail

PID_DIR="${PINCHTAB_PID_DIR:-/tmp/pinchtab-skill}"
LOG_DIR="${PINCHTAB_LOG_DIR:-$PID_DIR/logs}"
DISPLAY_NUM="${PINCHTAB_DISPLAY_NUM:-99}"
DISPLAY_VAR=":${DISPLAY_NUM}"
PORT="${BRIDGE_PORT:-9867}"
BIND="${BRIDGE_BIND:-127.0.0.1}"
START_XVFB="${PINCHTAB_START_XVFB:-1}"
START_TUNNEL="${PINCHTAB_START_TUNNEL:-0}"

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
    return
  fi

  local -a env_cmd
  env_cmd=(env "BRIDGE_PORT=$PORT" "BRIDGE_BIND=$BIND")
  if [ -n "${BRIDGE_TOKEN:-}" ]; then
    env_cmd+=("BRIDGE_TOKEN=$BRIDGE_TOKEN")
  fi
  if [ -n "${CHROME_BIN:-}" ]; then
    env_cmd+=("CHROME_BIN=$CHROME_BIN")
  fi
  if [ -n "${DISPLAY:-}" ]; then
    env_cmd+=("DISPLAY=$DISPLAY")
  fi

  nohup "${env_cmd[@]}" pinchtab >"$LOG_DIR/pinchtab.log" 2>&1 &
  echo $! >"$PID_DIR/pinchtab.pid"

  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done

  echo "PinchTab orchestrator did not become healthy." >&2
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

  nohup cloudflared tunnel --url "http://127.0.0.1:$PORT" --config /dev/null >"$LOG_DIR/cloudflared.log" 2>&1 &
  echo $! >"$PID_DIR/cloudflared.pid"
}

read_tunnel_url() {
  if [ "$START_TUNNEL" != "1" ]; then
    return
  fi

  for _ in $(seq 1 20); do
    local url
    url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | head -1 || true)
    if [ -n "$url" ]; then
      echo "$url"
      return
    fi
    sleep 1
  done
}

ensure_pinchtab
ensure_xvfb
start_orchestrator
start_tunnel

TUNNEL_URL="$(read_tunnel_url || true)"
PID_LINES="    \"pinchtab\": $(cat "$PID_DIR/pinchtab.pid")"
if [ -f "$PID_DIR/xvfb.pid" ]; then
  PID_LINES="${PID_LINES},
    \"xvfb\": $(cat "$PID_DIR/xvfb.pid")"
fi
if [ -f "$PID_DIR/cloudflared.pid" ]; then
  PID_LINES="${PID_LINES},
    \"cloudflared\": $(cat "$PID_DIR/cloudflared.pid")"
fi

cat <<EOF
{
  "healthUrl": "http://127.0.0.1:$PORT/health",
  "dashboardUrl": "http://127.0.0.1:$PORT/dashboard",
  "bind": "$BIND",
  "port": $PORT,
  "display": "${DISPLAY:-}",
  "tunnelUrl": "${TUNNEL_URL:-}",
  "pids": {
${PID_LINES}
  }
}
EOF
