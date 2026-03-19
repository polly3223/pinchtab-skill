#!/usr/bin/env bash
set -euo pipefail

echo "=== PinchTab Skill: install / verify dependencies ==="

install_pinchtab() {
  if command -v pinchtab >/dev/null 2>&1; then
    echo "  ✓ pinchtab already installed: $(command -v pinchtab)"
    return
  fi

  echo "  → Installing PinchTab via official installer"
  curl -fsSL https://pinchtab.com/install.sh | bash
}

install_linux_browser_deps() {
  if [ "$(uname -s)" != "Linux" ]; then
    echo "  → Non-Linux host detected, skipping apt-based Chrome/Xvfb install"
    return
  fi

  if ! command -v sudo >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
    echo "  → Linux host without sudo/apt-get, skipping Chrome/Xvfb install"
    return
  fi

  local need_update=0
  if ! command -v google-chrome-stable >/dev/null 2>&1; then
    need_update=1
  fi
  if ! command -v Xvfb >/dev/null 2>&1; then
    need_update=1
  fi
  if ! command -v x11vnc >/dev/null 2>&1; then
    need_update=1
  fi
  if ! command -v novnc_proxy >/dev/null 2>&1 && ! [ -x /usr/share/novnc/utils/novnc_proxy ]; then
    need_update=1
  fi

  if [ "$need_update" -eq 0 ]; then
    echo "  ✓ Chrome + Xvfb + x11vnc + novnc already available"
    return
  fi

  echo "  → Installing Chrome + Xvfb + x11vnc + novnc on apt-based Linux"
  sudo mkdir -p /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/google-chrome.gpg ]; then
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
  fi

  if [ ! -f /etc/apt/sources.list.d/google-chrome.list ]; then
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
      | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
  fi

  sudo apt-get update -qq
  sudo apt-get install -y google-chrome-stable xvfb x11vnc novnc
}

verify_optional() {
  if command -v cloudflared >/dev/null 2>&1; then
    echo "  ✓ cloudflared found: $(command -v cloudflared)"
  else
    echo "  · cloudflared not found (optional; only needed for quick public tunnels)"
  fi
}

install_pinchtab
install_linux_browser_deps

echo ""
echo "=== Verification ==="

missing=0
for cmd in pinchtab; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $cmd: $(command -v "$cmd")"
  else
    echo "  ✗ missing: $cmd"
    missing=1
  fi
done

if command -v google-chrome-stable >/dev/null 2>&1; then
  echo "  ✓ google-chrome-stable: $(command -v google-chrome-stable)"
elif command -v chromium >/dev/null 2>&1; then
  echo "  ✓ chromium: $(command -v chromium)"
elif command -v chromium-browser >/dev/null 2>&1; then
  echo "  ✓ chromium-browser: $(command -v chromium-browser)"
else
  echo "  ✗ missing: Chrome/Chromium (required for browser automation)"
  missing=1
fi

if command -v Xvfb >/dev/null 2>&1; then
  echo "  ✓ Xvfb: $(command -v Xvfb)"
else
  echo "  · Xvfb not found (needed for headed workflows on headless Linux)"
fi

if command -v x11vnc >/dev/null 2>&1; then
  echo "  ✓ x11vnc: $(command -v x11vnc)"
else
  echo "  · x11vnc not found (optional; needed for --vnc remote visual auth)"
fi

if command -v novnc_proxy >/dev/null 2>&1 || [ -x /usr/share/novnc/utils/novnc_proxy ]; then
  echo "  ✓ novnc: found"
else
  echo "  · novnc not found (optional; needed for --vnc remote visual auth)"
fi

verify_optional

echo ""
if [ "$missing" -eq 0 ]; then
  echo "=== Done ==="
else
  echo "=== Missing required dependencies ==="
  exit 1
fi
