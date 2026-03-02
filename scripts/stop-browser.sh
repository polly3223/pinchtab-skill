#!/usr/bin/env bash
# Stop all browser automation processes and clean up
set -euo pipefail

PID_DIR="/tmp/browser-automation"

if [ ! -d "$PID_DIR" ]; then
  echo "No browser automation session found."
  exit 0
fi

echo "Stopping browser automation stack..."

# Kill in reverse order (tunnel first, display last)
for service in cloudflared websockify x11vnc chrome xvfb; do
  PID_FILE="$PID_DIR/${service}.pid"
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      echo "  Stopping $service (PID $PID)..."
      kill "$PID" 2>/dev/null || true
      # Wait up to 5 seconds for graceful shutdown
      for i in $(seq 1 10); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.5
      done
      # Force kill if still alive
      if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null || true
        echo "    Force-killed $service"
      fi
    else
      echo "  $service (PID $PID) already stopped"
    fi
    rm -f "$PID_FILE"
  fi
done

# Clean up temp files
rm -rf /tmp/browser-automation/chrome-profile
rm -rf "$PID_DIR/logs"
rmdir "$PID_DIR" 2>/dev/null || rm -rf "$PID_DIR"

echo "All browser automation processes stopped."
