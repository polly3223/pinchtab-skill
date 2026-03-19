#!/usr/bin/env bash
set -euo pipefail

PID_DIR="${PINCHTAB_PID_DIR:-/tmp/pinchtab-skill}"

if [ ! -d "$PID_DIR" ]; then
  echo "No PinchTab helper session found."
  exit 0
fi

stop_pid() {
  local name="$1"
  local file="$PID_DIR/$name.pid"

  if [ ! -f "$file" ]; then
    return
  fi

  local pid
  pid="$(cat "$file")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$file"
}

stop_pid cloudflared-vnc
stop_pid novnc
stop_pid x11vnc
stop_pid cloudflared
stop_pid pinchtab
stop_pid xvfb

if [ -d "$PID_DIR/logs" ]; then
  rm -rf "$PID_DIR/logs"
fi

rmdir "$PID_DIR" 2>/dev/null || true

echo "Stopped PinchTab helper processes."
