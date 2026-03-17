---
name: pinchtab-browser-automation
description: Use PinchTab to browse the web, inspect authenticated pages, and interact with websites through an orchestrator, browser instances, and tabs. Prefer this for durable browser automation, repeated workflows, and login-preserving tasks.
---

# PinchTab Browser Automation

PinchTab is a browser-control layer for agents. It runs a local orchestrator, manages browser instances, and exposes a tab-scoped HTTP API for reading and interacting with pages.

This skill standardizes on the current orchestrator workflow:

1. start PinchTab
2. create or reuse an instance
3. open a tab
4. inspect with `text`, `snapshot`, or `find`
5. interact through stable refs with `action`
6. capture output with screenshots or PDFs when needed

## When To Use This Skill

Use this skill when the task requires:

- reading rendered pages
- handling authenticated websites
- repeating browser workflows with persistent state
- interacting with forms, buttons, links, and dashboards
- capturing screenshots or PDFs from a real browser

Do not use this skill for simple public pages when plain HTTP fetch is enough.

## Mental Model

### Orchestrator

The orchestrator runs with:

```bash
pinchtab
```

Default base URL:

```text
http://127.0.0.1:9867
```

It manages browser instances and exposes the dashboard.

### Instance

An instance is a real Chrome process with isolated state:

- cookies
- local storage
- history
- tabs

Instances can be:

- headless
- headed
- backed by a persistent profile

### Tab

Tabs are the main execution surface.

The most important tab routes are:

- `GET /tabs/<tabId>/text`
- `GET /tabs/<tabId>/snapshot`
- `POST /tabs/<tabId>/find`
- `POST /tabs/<tabId>/action`
- `GET /tabs/<tabId>/screenshot`
- `GET /tabs/<tabId>/pdf`

## Quick Workflow

### 1. Check Health

```bash
curl http://127.0.0.1:9867/health
```

If PinchTab is not running:

```bash
bash scripts/start-pinchtab.sh
```

### 2. Create an Instance

```bash
INST=$(pinchtab instance launch --mode headless | jq -r '.id')
sleep 2
```

If you need a reusable authenticated session, create or reuse a profile.

### 3. Open a Tab

```bash
TAB=$(curl -s -X POST http://127.0.0.1:9867/instances/$INST/tabs/open \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}' | jq -r '.id // .tabId')
```

### 4. Inspect The Page

Prefer these in order:

1. `text`
2. `snapshot?interactive=true&compact=true`
3. `find`
4. full `snapshot`
5. screenshot

Examples:

```bash
curl "http://127.0.0.1:9867/tabs/$TAB/text"
curl "http://127.0.0.1:9867/tabs/$TAB/snapshot?interactive=true&compact=true"
curl -X POST "http://127.0.0.1:9867/tabs/$TAB/find" \
  -H "Content-Type: application/json" \
  -d '{"query":"submit button"}'
```

### 5. Interact

```bash
curl -X POST http://127.0.0.1:9867/tabs/$TAB/action \
  -H "Content-Type: application/json" \
  -d '{"kind":"click","ref":"e5"}'
```

Common actions:

- `click`
- `type`
- `fill`
- `press`
- `hover`
- `select`
- `focus`

### 6. Verify

After every mutation:

- re-read with `snapshot` or `text`
- only use screenshots when structural verification is not enough

## Authenticated Work

Preferred approach:

1. create a persistent profile
2. start a headed instance with that profile
3. log in once
4. stop the instance
5. restart the same profile later

This is the main upstream model for keeping sessions alive.

### Cookie Import

Cookie import is still useful as a practical fallback if a user already has authenticated cookies in another browser, but it is not the primary workflow this skill emphasizes.

Use profiles first.

## Helpful Commands

### Launch

```bash
bun run scripts/pinchtab-client.ts launch --mode headless
bun run scripts/pinchtab-client.ts launch --mode headed --profile-id <profileId>
```

### Open/Navigate

```bash
bun run scripts/pinchtab-client.ts open <instanceId> https://example.com
bun run scripts/pinchtab-client.ts navigate-tab <tabId> https://example.com/next
```

### Read

```bash
bun run scripts/pinchtab-client.ts text <tabId>
bun run scripts/pinchtab-client.ts text <tabId> --raw
bun run scripts/pinchtab-client.ts snapshot <tabId> --interactive --compact
```

### Act

```bash
bun run scripts/pinchtab-client.ts click <tabId> e5
bun run scripts/pinchtab-client.ts type <tabId> e3 "hello"
bun run scripts/pinchtab-client.ts fill <tabId> e3 "user@example.com"
```

### Search / Ref Recovery

```bash
bun run scripts/pinchtab-client.ts find <tabId> "login button"
```

### Evaluate

```bash
bun run scripts/pinchtab-client.ts eval <instanceId> "document.title"
```

### Artifacts

```bash
bun run scripts/pinchtab-client.ts screenshot <tabId> /tmp/page.jpg
bun run scripts/pinchtab-client.ts pdf <tabId> /tmp/page.pdf
```

## Practical Heuristics

### Default Reading Strategy

- `text` for content
- compact interactive `snapshot` for actions
- `find` when the right ref is not obvious

### When To Use Headed Mode

Use headed mode when:

- the site behaves differently under headless mode
- you need to watch the login flow
- debugging selectors or page transitions matters

### When To Use Screenshots

Use screenshots only when:

- layout matters
- visual confirmation matters
- `text` and `snapshot` are insufficient

### Cleanup

Stop instances you no longer need.

If you started the orchestrator with the helper scripts, stop it with:

```bash
bash scripts/stop-pinchtab.sh
```

## Security

PinchTab gives full control of a real browser session.

Treat these as sensitive:

- profile directories
- screenshots and PDFs from private pages
- exported cookies
- any remote PinchTab endpoint

If exposing PinchTab remotely, use an auth token and network restrictions.

## Important Upstream Notes

Current PinchTab docs show both:

- top-level shorthand routes like `/navigate`, `/text`, `/action`
- orchestrator routes like `/instances/*` and `/tabs/*`

This skill prefers orchestrator routes for durable agent work.

Also note:

- docs prominently use `BRIDGE_TOKEN`
- the marketing site mentions `PINCHTAB_TOKEN`

This skill follows the orchestrator docs naming.
