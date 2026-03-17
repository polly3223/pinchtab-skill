# PinchTab Skill

[PinchTab](https://pinchtab.com/) is a 12 MB Go binary that launches Chrome and exposes a token-efficient HTTP + CLI interface for AI agents. No config, no dependencies — just install and go.

This repo wraps PinchTab into a ready-to-use skill for AI agent workflows (Claude, Codex, etc.). It includes:

- helper scripts to install, start, and stop PinchTab on a Linux server
- a Bun CLI client that covers the full HTTP API
- a `SKILL.md` that agents can read to learn the workflow
- tested and verified against PinchTab v0.7.6

## Why PinchTab

| Approach | Tokens |
|----------|--------|
| Full browser snapshot | ~10,000 |
| PinchTab snapshot (no filter) | ~3,000 |
| PinchTab snapshot (interactive + compact) | <1,000 |
| Plain HTTP fetch (no JS) | ~2,000 |

PinchTab gives you a real browser (JS rendering, cookies, auth sessions) at near-fetch token cost.

## Quick Start

### 1. Install

```bash
bash scripts/install-deps.sh
```

Installs PinchTab, Google Chrome, and Xvfb (on apt-based Linux). Or install manually:

```bash
curl -fsSL https://pinchtab.com/install.sh | bash
```

### 2. Start the Server

```bash
bash scripts/start-pinchtab.sh
```

Starts PinchTab on `http://127.0.0.1:9867`. Outputs JSON with health URL, dashboard URL, PIDs.

On Linux servers where Chrome needs `--no-sandbox`, set `CHROME_BINARY` to point to a wrapper:

```bash
# Create wrapper (one-time)
mkdir -p ~/.pinchtab
cat > ~/.pinchtab/chrome-wrapper.sh << 'EOF'
#!/bin/bash
exec /usr/bin/google-chrome-stable --no-sandbox --disable-gpu "$@"
EOF
chmod +x ~/.pinchtab/chrome-wrapper.sh

# Start with wrapper
CHROME_BINARY=~/.pinchtab/chrome-wrapper.sh bash scripts/start-pinchtab.sh
```

### 3. Browse a Page

```bash
# Navigate
pinchtab nav https://news.ycombinator.com

# Read text (token-efficient)
pinchtab text

# Get interactive elements
pinchtab snap -i -c

# Click an element
pinchtab click e5

# Type into an input
pinchtab type e12 "search query"

# Screenshot
pinchtab ss -o /tmp/page.jpg
```

### 4. Stop

```bash
bash scripts/stop-pinchtab.sh
```

## How It Works

### Single-Browser Mode (Default)

`pinchtab` starts a server on port 9867 with one Chrome instance. You interact via shorthand routes:

| Route | Method | Description |
|-------|--------|-------------|
| `/health` | GET | Server status |
| `/navigate` | POST | Go to URL (`{"url":"..."}`) |
| `/text` | GET | Readable text extraction |
| `/snapshot` | GET | Accessibility tree |
| `/action` | POST | Click, type, fill, press, hover, select, focus, scroll |
| `/screenshot` | GET | JPEG screenshot (`?raw=true` for binary) |
| `/pdf` | GET | PDF export (`?raw=true` for binary) |
| `/evaluate` | POST | Run JavaScript (`{"expression":"..."}`) |
| `/tabs` | GET | List open tabs |

### Multi-Instance Mode

For isolated sessions (e.g., different logins), launch named instances:

```bash
# Launch an instance (gets its own Chrome + port)
curl -X POST http://127.0.0.1:9867/instances/launch \
  -H "Content-Type: application/json" \
  -d '{"name":"scraper","port":"9868","headless":true}'

# Talk to the instance on its own port — same shorthand routes
curl -X POST http://127.0.0.1:9868/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'

curl http://127.0.0.1:9868/text

# List / stop instances
curl http://127.0.0.1:9867/instances
curl -X POST http://127.0.0.1:9867/instances/scraper-9868/stop
```

Each instance gets its own profile directory (`~/.pinchtab/profiles/<name>/`) for persistent cookies and sessions.

### Authenticated Browsing

1. Start a headed instance (needs Xvfb on servers)
2. Log in via the PinchTab dashboard screencast
3. Stop the instance
4. Restart with the same profile name later — session persists

## CLI Reference

```
pinchtab nav <url>                     Navigate to URL
pinchtab text [--raw]                  Extract readable text
pinchtab snap [-i] [-c] [-d]          Accessibility tree snapshot
pinchtab click <ref>                   Click element by ref (e.g., e5)
pinchtab type <ref> <text>             Type into element
pinchtab fill <ref|selector> <text>    Fill input directly
pinchtab press <key>                   Press key (Enter, Tab, Escape...)
pinchtab hover <ref>                   Hover element
pinchtab scroll <ref|pixels>           Scroll to element or by pixels
pinchtab select <ref> <value>          Select dropdown option
pinchtab focus <ref>                   Focus element
pinchtab tabs [new <url>|close <id>]   Manage tabs
pinchtab ss [-o file] [-q 80]          Screenshot (JPEG)
pinchtab pdf [-o file] [--landscape]   Export page as PDF
pinchtab eval <expression>             Run JavaScript
pinchtab health                        Check server status
```

Snapshot flags: `-i` interactive only, `-c` compact, `-d` diff since last, `-s <css>` scope to selector, `--max-tokens N`, `--depth N`, `--tab <id>`.

## Bun Client

A zero-dependency Bun CLI that wraps the HTTP API:

```bash
bun run scripts/pinchtab-client.ts health
bun run scripts/pinchtab-client.ts launch --name scraper --port 9868
bun run scripts/pinchtab-client.ts navigate 9868 https://example.com
bun run scripts/pinchtab-client.ts text 9868
bun run scripts/pinchtab-client.ts snapshot 9868 --interactive --compact
bun run scripts/pinchtab-client.ts click 9868 e5
bun run scripts/pinchtab-client.ts screenshot 9868 /tmp/page.jpg
bun run scripts/pinchtab-client.ts stop scraper-9868
bun run scripts/pinchtab-client.ts list-instances
```

Defaults to the main server port (9867). Pass a port number to target a specific instance.

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/install-deps.sh` | Install PinchTab + Chrome + Xvfb |
| `scripts/start-pinchtab.sh` | Start server, Xvfb, optional tunnel |
| `scripts/stop-pinchtab.sh` | Stop all managed processes |
| `scripts/pinchtab-client.ts` | Bun HTTP client for the API |

### start-pinchtab.sh Options

```bash
bash scripts/start-pinchtab.sh              # default: start with Xvfb
bash scripts/start-pinchtab.sh --no-xvfb    # skip Xvfb (headless only)
bash scripts/start-pinchtab.sh --tunnel      # also start cloudflared tunnel
```

Environment overrides: `BRIDGE_PORT`, `BRIDGE_BIND`, `BRIDGE_TOKEN`, `CHROME_BINARY`, `PINCHTAB_START_XVFB`, `PINCHTAB_START_TUNNEL`.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PINCHTAB_URL` | `http://127.0.0.1:9867` | Server URL (for CLI) |
| `PINCHTAB_TOKEN` | — | Auth token (CLI) |
| `BRIDGE_PORT` | `9867` | Server port |
| `BRIDGE_BIND` | `127.0.0.1` | Bind address |
| `BRIDGE_TOKEN` | — | Auth token (server) |
| `BRIDGE_HEADLESS` | `true` | Run Chrome headless |
| `CHROME_BINARY` | — | Path to Chrome binary or wrapper |

## Security

PinchTab controls a real browser with real login sessions. Treat as sensitive:

- profile directories (`~/.pinchtab/profiles/`)
- screenshots and PDFs from private pages
- exported cookies
- any PinchTab endpoint exposed beyond localhost

If exposing remotely: set `BRIDGE_TOKEN`, restrict network access, start with low-risk accounts.

## Repo Layout

```
pinchtab-skill/
├── README.md                    # This file
├── SKILL.md                     # Agent-readable skill definition
└── scripts/
    ├── install-deps.sh          # Dependency installer
    ├── pinchtab-client.ts       # Bun HTTP API client
    ├── start-pinchtab.sh        # Start server + Xvfb + tunnel
    └── stop-pinchtab.sh         # Stop managed processes
```

## Links

- [PinchTab website](https://pinchtab.com/)
- [PinchTab docs](https://pinchtab.com/docs/)
- [PinchTab GitHub](https://github.com/nickvdyck/pinchtab)

## License

MIT
