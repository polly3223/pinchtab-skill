# PinchTab Skill Wrapper

This repo mirrors the official upstream PinchTab skill and keeps only a few local bootstrap helpers around it.

## Keep

- `SKILL.md`, `TRUST.md`, `agents/openai.yaml`, and `references/`: upstream skill content
- `scripts/install-deps.sh`: install and verify PinchTab plus host dependencies
- `scripts/start-pinchtab.sh`: start a local PinchTab server with sane defaults
- `scripts/stop-pinchtab.sh`: stop the helper-managed processes

## Drop

The repo no longer carries its own Bun client. PinchTab’s own CLI and HTTP API are the primary interface now.

## Quick Start

```bash
bash scripts/install-deps.sh
PINCHTAB_TOKEN=your-token bash scripts/start-pinchtab.sh
pinchtab health
pinchtab nav https://example.com
pinchtab snap -i -c
```

## Current Read

- The skill/control-plane problem is mostly solved by using upstream PinchTab directly.
- The hard open problem is browser acquisition and login reliability for social sites.
- In our testing, PinchTab-managed login on `x.com` was unreliable enough that auth bootstrap should be treated as a separate problem.
