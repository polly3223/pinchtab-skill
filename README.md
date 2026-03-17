# PinchTab Skill

PinchTab is a lightweight browser-control layer for AI agents: a small binary that launches Chrome and exposes a token-efficient HTTP API.

This repo packages the current PinchTab workflow for agent use:

- start the PinchTab orchestrator
- create isolated browser instances
- open tabs inside those instances
- read pages with `text` or `snapshot`
- interact with pages through stable element refs
- keep authenticated browser state alive through persistent profiles

This refresh aligns the repo with the current PinchTab docs as of March 17, 2026.

## What This Repo Gives You

- a clearer mental model for PinchTab's current architecture
- an updated `SKILL.md` for Claude/Codex-style agent workflows
- helper scripts to start and stop the PinchTab orchestrator on a server
- a zero-dependency Bun CLI for the PinchTab HTTP API
- a better README for sharing the experiment internally

## Current PinchTab Model

The official docs currently show two ways of thinking about PinchTab:

1. Quick single-browser shorthand
   - CLI like `pinchtab nav`, `pinchtab snap -i -c`, `pinchtab text`
   - HTTP routes like `/navigate`, `/snapshot`, `/text`, `/action`

2. Orchestrator + instances + tabs
   - start the orchestrator with `pinchtab`
   - create browser instances with `pinchtab instance launch`
   - open tabs in a specific instance
   - operate on tabs through `/tabs/<tabId>/*`

For agent workflows, this repo standardizes on the second model:

- `pinchtab` runs the orchestrator on port `9867`
- each instance is a real isolated Chrome process
- each tab is the execution surface
- authenticated state lives in profiles, not in ad-hoc cookies alone

That model is more durable for:

- repeated automations
- multiple sessions
- authenticated browsing
- future multi-agent coordination

## Quick Start

### 1. Install PinchTab

Official install:

```bash
curl -fsSL https://pinchtab.com/install.sh | bash
pinchtab --version
```

If you are on a Linux server and want headed debugging, make sure Chrome and Xvfb are available too.

### 2. Start the Orchestrator

```bash
bash scripts/start-pinchtab.sh
```

This starts the orchestrator on `http://127.0.0.1:9867` and prints connection info as JSON.

### 3. Launch an Instance

```bash
INST=$(bun run scripts/pinchtab-client.ts launch --mode headless | jq -r '.id')
```

Or directly with the CLI:

```bash
INST=$(pinchtab instance launch --mode headless | jq -r '.id')
```

### 4. Open a Tab

```bash
bun run scripts/pinchtab-client.ts open "$INST" https://example.com
```

Response includes the `tabId`.

### 5. Read the Page

```bash
bun run scripts/pinchtab-client.ts text <tabId>
bun run scripts/pinchtab-client.ts snapshot <tabId> --interactive --compact
```

### 6. Interact with the Page

```bash
bun run scripts/pinchtab-client.ts click <tabId> e5
bun run scripts/pinchtab-client.ts fill <tabId> e3 "hello@example.com"
```

### 7. Stop the Instance

```bash
bun run scripts/pinchtab-client.ts stop "$INST"
```

## Architecture

### Orchestrator

Start it with:

```bash
pinchtab
```

Responsibilities:

- listens on port `9867` by default
- manages running instances
- exposes the dashboard
- routes requests to instance- and tab-scoped APIs

### Instance

An instance is a real Chrome browser process:

- isolated cookies, history, and storage
- can be headless or headed
- can use a persistent profile
- can contain one or more tabs

### Tab

A tab is the surface you actually automate:

- `snapshot` for structure
- `text` for token-efficient reading
- `action` for click/type/fill/press/hover/select/focus
- `screenshot` and `pdf` for artifacts

## Recommended Agent Workflow

### Fast Read-Only Task

Use:

- `text`
- `snapshot?interactive=true&compact=true`

Avoid screenshots unless you truly need pixels.

### Authenticated Task

Use:

1. a persistent profile
2. a headed instance for the first login
3. restart that same profile later for reuse

Official docs emphasize profile persistence. That should be your default mental model.

### Cookie Import

Cookie import is still a useful practical trick when you already have authenticated cookies from another browser, but it should be treated as a convenience workflow rather than the core PinchTab model.

Use profiles first.

## Current HTTP Surface We Standardize On

### Health

```bash
curl http://127.0.0.1:9867/health
```

### Launch Instance

```bash
curl -X POST http://127.0.0.1:9867/instances/launch \
  -H "Content-Type: application/json" \
  -d '{"mode":"headless"}'
```

Notes:

- some current docs also show `POST /instances/start` when launching from a profile
- this repo supports both when practical

### Open Tab

```bash
curl -X POST http://127.0.0.1:9867/instances/<instanceId>/tabs/open \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'
```

### Read Text

```bash
curl "http://127.0.0.1:9867/tabs/<tabId>/text"
curl "http://127.0.0.1:9867/tabs/<tabId>/text?raw=true"
```

### Read Snapshot

```bash
curl "http://127.0.0.1:9867/tabs/<tabId>/snapshot"
curl "http://127.0.0.1:9867/tabs/<tabId>/snapshot?interactive=true&compact=true"
```

### Find a Likely Ref

```bash
curl -X POST http://127.0.0.1:9867/tabs/<tabId>/find \
  -H "Content-Type: application/json" \
  -d '{"query":"login button"}'
```

### Interact

```bash
curl -X POST http://127.0.0.1:9867/tabs/<tabId>/action \
  -H "Content-Type: application/json" \
  -d '{"kind":"click","ref":"e5"}'
```

Other common actions:

- `type`
- `fill`
- `press`
- `hover`
- `select`
- `focus`

### Evaluate JavaScript

```bash
curl -X POST http://127.0.0.1:9867/instances/<instanceId>/evaluate \
  -H "Content-Type: application/json" \
  -d '{"expression":"document.title"}'
```

### Export Artifacts

```bash
curl "http://127.0.0.1:9867/tabs/<tabId>/screenshot?raw=true" > page.jpg
curl "http://127.0.0.1:9867/tabs/<tabId>/pdf?raw=true" > page.pdf
```

## Scripts

### `scripts/install-deps.sh`

Installs or verifies:

- PinchTab
- Chrome on apt-based Linux hosts
- Xvfb for headed server workflows
- optional `cloudflared`

### `scripts/start-pinchtab.sh`

Starts:

- Xvfb on `:99` when requested
- the PinchTab orchestrator
- an optional Cloudflare quick tunnel

Outputs JSON with:

- local health URL
- dashboard URL
- local port
- optional public tunnel URL

### `scripts/stop-pinchtab.sh`

Stops the processes created by `start-pinchtab.sh`.

### `scripts/pinchtab-client.ts`

Zero-dependency Bun CLI around the current PinchTab HTTP API.

Supported commands:

- `health`
- `launch`
- `list-instances`
- `list-tabs`
- `open`
- `navigate-tab`
- `text`
- `snapshot`
- `find`
- `click`
- `type`
- `fill`
- `eval`
- `cookies`
- `screenshot`
- `pdf`
- `stop`

## Security Notes

PinchTab controls a real browser with real login sessions.

Treat these as sensitive:

- profile directories
- screenshots and PDFs from private sites
- exported cookies
- any remote PinchTab endpoint exposed beyond localhost

If you expose PinchTab remotely:

- set an auth token
- restrict who can reach it
- use low-risk accounts first

The upstream site mentions `PINCHTAB_TOKEN`, while the docs and build examples prominently use `BRIDGE_TOKEN`.

For now, this repo follows the documented orchestrator environment names:

- `BRIDGE_PORT`
- `BRIDGE_BIND`
- `BRIDGE_TOKEN`

## Upstream Docs Reality Check

PinchTab is moving fast, and the current official docs show a few parallel patterns at once:

- top-level shorthand routes
- orchestrator + instances + tabs
- `instances/launch`
- `instances/start` in some profile examples

This repo makes one opinionated choice:

- prefer the orchestrator + instance + tab model for serious agent workflows

That keeps the repo internally coherent even if upstream examples vary.

## Repo Layout

```text
pinchtab-skill/
├── README.md
├── SKILL.md
└── scripts/
    ├── browser-connect.ts      # compatibility wrapper
    ├── install-deps.sh
    ├── launch-browser.sh       # compatibility wrapper
    ├── pinchtab-client.ts
    ├── start-pinchtab.sh
    ├── stop-browser.sh         # compatibility wrapper
    └── stop-pinchtab.sh
```

## Official Sources

- Repo: https://github.com/polly3223/pinchtab-skill
- Site: https://pinchtab.com/
- Docs: https://pinchtab.com/docs/
- Getting started: https://pinchtab.com/docs/get-started
- Tabs reference: https://pinchtab.com/docs/tabs/

## License

MIT
