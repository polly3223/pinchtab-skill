# PinchTab — Browser Automation for AI Agents

A comprehensive guide and toolkit for AI agents to automate web browsing via [PinchTab](https://pinchtab.com) — a lightweight HTTP API that controls Chrome. Token-efficient: you get exactly the data you ask for, nothing more.

Originally built as an [AI agent skill](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/tutorials#add-custom-slash-commands) (see `SKILL.md`), but the API docs, patterns, and scripts are useful for any AI agent framework.

## Architecture

- **PinchTab** (`/usr/local/bin/pinchtab`) — 12MB Go binary, wraps Chrome DevTools Protocol into HTTP API
- **Google Chrome** (`/usr/bin/google-chrome-stable`) — installed via apt
- **Xvfb** — virtual display for headed mode on a headless server
- **Chrome wrapper** (`~/.pinchtab/chrome-wrapper.sh`) — adds `--no-sandbox` for server environments

PinchTab runs Chrome with persistent profiles. Once a user logs into a site, the session persists across restarts.

## Quick Start

### Installation

Install PinchTab from [pinchtab.com](https://pinchtab.com), then ensure Chrome and Xvfb are available:

```bash
# Install Google Chrome
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt-get update && sudo apt-get install -y google-chrome-stable xvfb

# Create Chrome wrapper for headless servers
mkdir -p ~/.pinchtab
cat > ~/.pinchtab/chrome-wrapper.sh << 'EOF'
#!/bin/bash
exec /usr/bin/google-chrome-stable --no-sandbox "$@"
EOF
chmod +x ~/.pinchtab/chrome-wrapper.sh
```

### Dashboard Mode (multiple profiles)

```bash
# Ensure Xvfb is running
pgrep Xvfb || (Xvfb :99 -screen 0 1920x1080x24 &>/dev/null &)

# Start PinchTab dashboard
DISPLAY=:99 \
CHROME_BINARY=~/.pinchtab/chrome-wrapper.sh \
CHROME_FLAGS="--no-sandbox --disable-gpu" \
nohup pinchtab dashboard > /tmp/pinchtab-dash.log 2>&1 &

# Dashboard is at http://localhost:9867
```

### Launch a Profile

```bash
# Via dashboard API
curl -s -X POST http://localhost:9867/instances/launch \
  -H "Content-Type: application/json" \
  -d '{"name":"my-profile","port":"9868","headless":false}'
```

Each profile runs on its own port (9868, 9869, etc). The API for that profile is at `http://localhost:<port>`.

### Single Profile (no dashboard)

```bash
pgrep Xvfb || (Xvfb :99 -screen 0 1920x1080x24 &>/dev/null &)

DISPLAY=:99 \
CHROME_BINARY=~/.pinchtab/chrome-wrapper.sh \
BRIDGE_PORT=9868 \
BRIDGE_PROFILE=~/.pinchtab/profiles/default \
BRIDGE_HEADLESS=false \
BRIDGE_NO_RESTORE=true \
nohup pinchtab > /tmp/pinchtab.log 2>&1 &
```

## Authentication — Cookie Import

PinchTab doesn't need screen sharing or VNC for login. Instead, use the **Cookie-Editor** browser extension to export cookies from the user's own browser.

### What the User Needs

The user installs this Chrome extension on their personal browser:

**Cookie-Editor**: https://chromewebstore.google.com/detail/hlkenndednhfkekhgcdicdfddnkalmdm

Free, open-source extension with 700K+ users — lets you view and export cookies from any website.

### Workflow

1. User goes to the target website (logged in) in their personal browser
2. User clicks Cookie-Editor icon, clicks "Export" — copies JSON to clipboard
3. User sends the JSON to the agent
4. Agent imports cookies into PinchTab (see below)

### Importing Cookies

```bash
# Navigate to the target domain first
curl -s -X POST http://localhost:9868/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://x.com"}'

# Then inject cookies
curl -s -X POST http://localhost:9868/cookies \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://x.com",
    "cookies": [
      {"name":"auth_token","value":"...","domain":".x.com","path":"/","secure":true,"httpOnly":true,"sameSite":"None","expires":1786701753},
      {"name":"ct0","value":"...","domain":".x.com","path":"/","secure":true,"httpOnly":false,"sameSite":"Lax","expires":1786701754}
    ]
  }'

# Reload the page — should now be authenticated
curl -s -X POST http://localhost:9868/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://x.com/home"}'
```

**Cookie format mapping** (Cookie-Editor -> PinchTab):
- `name`, `value`, `domain`, `path` -> same
- `secure` -> same (boolean)
- `httpOnly` -> same (boolean)
- `expirationDate` -> `expires` (rename, same value — Unix timestamp)
- `sameSite` -> capitalize: `"no_restriction"` -> `"None"`, `"lax"` -> `"Lax"`, `"strict"` -> `"Strict"`
- Ignore: `hostOnly`, `storeId`, `session`, `id`

### Cookie Persistence

Cookies are stored in the Chrome profile directory (`~/.pinchtab/profiles/<name>/`). They persist across PinchTab restarts. The user only needs to export cookies once per site — unless the session expires (typically weeks to months).

## PinchTab HTTP API

All calls are to the instance port (e.g., `http://localhost:9868`).

### Reading Content

```bash
# Get readable text from the page (most token-efficient)
curl -s http://localhost:9868/text
# Returns: {"text":"...", "title":"...", "url":"..."}

# Get interactive element snapshot (compact format)
curl -s "http://localhost:9868/snapshot?filter=interactive&format=compact"

# Get full element snapshot
curl -s http://localhost:9868/snapshot

# Take a screenshot
curl -s http://localhost:9868/screenshot -o /tmp/page.png

# Get all cookies for a URL
curl -s "http://localhost:9868/cookies?url=https://x.com"
```

### Navigation

```bash
# Go to a URL
curl -s -X POST http://localhost:9868/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'

# Get open tabs
curl -s http://localhost:9868/tabs
```

### Interaction

```bash
# Click an element by reference (from snapshot)
curl -s -X POST http://localhost:9868/action \
  -H "Content-Type: application/json" \
  -d '{"actions":[{"kind":"click","ref":"e5"}]}'

# Type into an element
curl -s -X POST http://localhost:9868/action \
  -H "Content-Type: application/json" \
  -d '{"actions":[{"kind":"type","ref":"e3","text":"hello world"}]}'

# Scroll down
curl -s -X POST http://localhost:9868/evaluate \
  -H "Content-Type: application/json" \
  -d '{"expression":"window.scrollBy(0, 1500)"}'

# Run arbitrary JavaScript
curl -s -X POST http://localhost:9868/evaluate \
  -H "Content-Type: application/json" \
  -d '{"expression":"document.title"}'
```

### Health & Status

```bash
curl -s http://localhost:9868/health
# Returns: {"cdp":"","status":"ok","tabs":1}
```

## Dashboard API (port 9867)

```bash
# List profiles
curl -s http://localhost:9867/profiles

# List running instances
curl -s http://localhost:9867/instances

# Launch a profile
curl -s -X POST http://localhost:9867/instances/launch \
  -H "Content-Type: application/json" \
  -d '{"name":"profile-name","port":"9868","headless":false}'

# Stop an instance
curl -s -X POST http://localhost:9867/instances/<id>/stop

# View instance logs
curl -s http://localhost:9867/instances/<id>/logs
```

## Common Patterns

### Scrape a Social Media Feed

```python
import json, time, urllib.request

BASE = "http://localhost:9868"

def post(path, data):
    req = urllib.request.Request(f"{BASE}{path}")
    req.add_header("Content-Type", "application/json")
    req.method = "POST"
    req.data = json.dumps(data).encode()
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())

def get_json(path):
    with urllib.request.urlopen(f"{BASE}{path}", timeout=15) as r:
        return json.loads(r.read())

# Navigate to feed
post("/navigate", {"url": "https://x.com/home"})
time.sleep(5)

# Scroll and collect tweets
all_tweets = {}
for i in range(30):
    result = post("/evaluate", {
        "expression": """JSON.stringify(Array.from(document.querySelectorAll('article')).map(a => {
            let timeEl = a.querySelector('time');
            return {
                raw: a.innerText.substring(0, 800),
                datetime: timeEl ? timeEl.getAttribute('datetime') : '',
                link: timeEl && timeEl.closest('a') ? timeEl.closest('a').href : ''
            };
        }))"""
    })
    articles = json.loads(result.get("result", "[]"))
    for a in articles:
        key = a.get("raw", "")[:150]
        if key and key not in all_tweets:
            all_tweets[key] = a

    if len(all_tweets) >= 100:
        break

    post("/evaluate", {"expression": "window.scrollBy(0, 1500)"})
    time.sleep(2)

tweets = list(all_tweets.values())
```

### Read a Specific Webpage

```bash
# Navigate
curl -s -X POST http://localhost:9868/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/article"}'
sleep 3

# Extract text
curl -s http://localhost:9868/text
```

### Take a Screenshot

```bash
curl -s http://localhost:9868/screenshot -o /tmp/page.png
```

### Check if Session is Still Valid

```bash
# Navigate to the authenticated page
curl -s -X POST http://localhost:9868/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://x.com/home"}'
sleep 4

# Check if we got the feed or a login page
TITLE=$(curl -s http://localhost:9868/text | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))")

if echo "$TITLE" | grep -qi "log in\|sign in\|join"; then
    echo "Session expired — need fresh cookies from user"
else
    echo "Session valid — authenticated"
fi
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CHROME_BINARY` | Path to Chrome or wrapper script | auto-detect |
| `CHROME_FLAGS` | Extra Chrome flags | — |
| `BRIDGE_PORT` | PinchTab API port | 9867 |
| `BRIDGE_PROFILE` | Chrome profile directory | — |
| `BRIDGE_HEADLESS` | Run Chrome headless | true |
| `BRIDGE_TOKEN` | Auth token for PinchTab API | — (disabled) |
| `BRIDGE_STEALTH` | Fingerprint stealth level | light |
| `BRIDGE_NO_RESTORE` | Don't restore previous tabs | false |
| `BRIDGE_NO_DASHBOARD` | Run without dashboard | false |
| `BRIDGE_BLOCK_MEDIA` | Block media loading | false |
| `BRIDGE_BLOCK_IMAGES` | Block image loading | false |
| `BRIDGE_NAV_TIMEOUT` | Navigation timeout | 30s |
| `BRIDGE_MAX_TABS` | Max concurrent tabs | — |
| `BRIDGE_TIMEZONE` | Override timezone | — |
| `BRIDGE_USER_AGENT` | Override user agent | — |

## Scripts

This repo includes helper scripts in `scripts/`:

- **`install-deps.sh`** — Installs system dependencies (Xvfb, x11vnc, noVNC) for the VNC-based approach
- **`launch-browser.sh`** — Launches the full VNC stack (Xvfb + Chromium + VNC + cloudflared tunnel) — useful if you need visual access to the browser
- **`stop-browser.sh`** — Stops all VNC stack processes
- **`browser-connect.ts`** — TypeScript/Bun CLI to interact with a running browser via CDP (puppeteer-core)

## Using as a Claude Code Skill

Drop `SKILL.md` into your Claude Code project's skills directory to give Claude browser automation capabilities:

```bash
mkdir -p .claude/skills
cp SKILL.md .claude/skills/browser-automation.md
```

Claude will then know how to start PinchTab, import cookies, scrape pages, and interact with authenticated websites.

## Tips

- **Always use `CHROME_BINARY=~/.pinchtab/chrome-wrapper.sh`** on servers — Chrome needs `--no-sandbox`
- **PinchTab dashboard + instances survive restarts** if launched with `nohup`
- **Cookie sessions persist** in the profile directory across restarts
- **`/text` is the most token-efficient** way to read pages — use it by default
- **`/evaluate` is the endpoint for JavaScript** (not `/eval`)
- **Scrolling**: use `evaluate` with `window.scrollBy(0, pixels)`
- **The user only needs Cookie-Editor once** — after importing cookies, sessions persist until they expire
- **Never store cookie JSON in plain text** — it contains auth tokens. Import it and discard.
- **Check session validity** before starting a scraping task — navigate and verify the page title isn't a login screen

## License

MIT
