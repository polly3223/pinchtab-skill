---
name: pinchtab-browser
description: Browse the web with a real Chrome browser. Read pages, click elements, fill forms, take screenshots, and maintain authenticated sessions. Token-efficient — use this instead of screenshots for most web tasks.
---

# PinchTab Browser Skill

PinchTab gives you a real Chrome browser controlled via HTTP. Use it when you need to:

- read pages that require JavaScript rendering
- interact with forms, buttons, and links
- maintain authenticated sessions (login once, reuse later)
- take screenshots or export PDFs
- scrape content that plain HTTP fetch can't handle

Do NOT use this for simple public pages — plain fetch is cheaper and faster.

## Check If PinchTab Is Running

```bash
curl -s http://127.0.0.1:9867/health
```

If not running:

```bash
CHROME_BINARY=~/.pinchtab/chrome-wrapper.sh bash scripts/start-pinchtab.sh --no-xvfb
```

## Core Workflow

### 1. Navigate

```bash
curl -s -X POST http://127.0.0.1:9867/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'
```

Or via CLI:

```bash
pinchtab nav https://example.com
```

### 2. Read the Page

Prefer these in order (cheapest first):

```bash
# Text extraction (~few hundred tokens)
pinchtab text

# Interactive elements only, compact (~<1000 tokens)
pinchtab snap -i -c

# Full accessibility tree (~3000 tokens)
pinchtab snap

# Screenshot (only when layout matters)
pinchtab ss -o /tmp/page.jpg
```

### 3. Interact

Elements are referenced by `ref` IDs from the snapshot (e.g., `e5`, `e12`).

```bash
pinchtab click e5
pinchtab type e12 "search query"
pinchtab fill e3 "user@example.com"
pinchtab press Enter
pinchtab hover e8
pinchtab select e10 "option-value"
pinchtab scroll e5
```

After every interaction, re-read with `text` or `snap -i -c` to verify the result.

### 4. Run JavaScript

```bash
pinchtab eval "document.title"
pinchtab eval "document.querySelector('.price').textContent"
```

### 5. Export

```bash
pinchtab ss -o /tmp/screenshot.jpg
pinchtab pdf -o /tmp/page.pdf
```

## HTTP API Reference

All routes on the server port (default 9867). For multi-instance, use the instance's own port.

```bash
# Navigation
POST /navigate                        {"url":"https://..."}

# Reading
GET  /text                            Readable text (add ?raw=true for unprocessed)
GET  /snapshot                        Accessibility tree
GET  /snapshot?interactive=true&compact=true   Interactive elements only

# Interaction
POST /action                          {"kind":"click","ref":"e5"}
POST /action                          {"kind":"type","ref":"e12","text":"hello"}
POST /action                          {"kind":"fill","ref":"e3","text":"value"}
POST /action                          {"kind":"press","ref":"","text":"Enter"}

# JavaScript
POST /evaluate                        {"expression":"document.title"}

# Artifacts
GET  /screenshot?raw=true             JPEG binary
GET  /pdf?raw=true                    PDF binary

# Management
GET  /health                          Server status
GET  /tabs                            List open tabs
```

## Multi-Instance (Isolated Sessions)

Launch separate Chrome instances for parallel or authenticated work:

```bash
# Launch
curl -s -X POST http://127.0.0.1:9867/instances/launch \
  -H "Content-Type: application/json" \
  -d '{"name":"mybot","port":"9868","headless":true}'

# Use it (same routes, different port)
curl -s -X POST http://127.0.0.1:9868/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}'

curl -s http://127.0.0.1:9868/text

# List running instances
curl -s http://127.0.0.1:9867/instances

# Stop
curl -s -X POST http://127.0.0.1:9867/instances/mybot-9868/stop
```

## Authenticated Browsing

1. Launch an instance with a name (creates a persistent profile)
2. Log in (via headed mode + dashboard, or by navigating and filling forms)
3. Stop the instance
4. Re-launch with the same name later — cookies and sessions persist in `~/.pinchtab/profiles/<name>/`

## Heuristics

- Always try `text` first — it's the cheapest read
- Use `snap -i -c` when you need to find clickable elements
- Only use screenshots when visual layout matters
- After clicking/typing, always re-read to verify the page changed
- Use `eval` for precise data extraction when DOM selectors are known
- Stop instances you no longer need
