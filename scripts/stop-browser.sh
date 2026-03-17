#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "stop-browser.sh is now a compatibility wrapper."
echo "Delegating to stop-pinchtab.sh..." >&2

exec bash "$SCRIPT_DIR/stop-pinchtab.sh" "$@"
