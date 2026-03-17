#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "launch-browser.sh is now a compatibility wrapper."
echo "Delegating to start-pinchtab.sh..." >&2

exec bash "$SCRIPT_DIR/start-pinchtab.sh" "$@"
