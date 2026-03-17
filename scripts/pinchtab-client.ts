#!/usr/bin/env bun

/**
 * PinchTab HTTP API client.
 * Zero dependencies — runs with `bun run`.
 *
 * By default talks to the main server on port 9867.
 * For instance-scoped commands, pass a port number as the first arg
 * and it targets http://127.0.0.1:<port> instead.
 */

const DEFAULT_PORT = 9867;
const HOST = process.env.PINCHTAB_HOST || "127.0.0.1";

function baseUrl(port: number): string {
  return `http://${HOST}:${port}`;
}

function usage(): never {
  console.error(`PinchTab Client — Bun HTTP wrapper for PinchTab API

Server commands (port 9867):
  health                                     Check server status
  launch --name <n> --port <p> [--headless]  Launch a new instance
  list-instances                             List running instances
  stop <instanceId>                          Stop an instance

Instance commands (pass port to target a specific instance):
  navigate <port> <url>                      Navigate to URL
  text <port> [--raw]                        Extract readable text
  snapshot <port> [--interactive] [--compact] Accessibility tree
  click <port> <ref>                         Click element
  type <port> <ref> <text>                   Type into element
  fill <port> <ref> <text>                   Fill input directly
  eval <port> <expression>                   Run JavaScript
  screenshot <port> [path]                   Save screenshot
  pdf <port> [path]                          Save PDF
  tabs <port>                                List open tabs

Examples:
  bun run scripts/pinchtab-client.ts health
  bun run scripts/pinchtab-client.ts launch --name scraper --port 9868
  bun run scripts/pinchtab-client.ts navigate 9868 https://example.com
  bun run scripts/pinchtab-client.ts text 9868
  bun run scripts/pinchtab-client.ts snapshot 9868 --interactive --compact
  bun run scripts/pinchtab-client.ts click 9868 e5
  bun run scripts/pinchtab-client.ts stop scraper-9868`);
  process.exit(1);
}

async function request(
  url: string,
  init?: RequestInit,
): Promise<Response> {
  const headers = new Headers(init?.headers);
  const token = process.env.PINCHTAB_TOKEN || process.env.BRIDGE_TOKEN;
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  if (init?.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const resp = await fetch(url, { ...init, headers });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`${resp.status} ${resp.statusText}: ${text}`);
  }

  return resp;
}

async function json(url: string, init?: RequestInit): Promise<unknown> {
  const resp = await request(url, init);
  return resp.json();
}

async function writeBinary(url: string, outputPath: string): Promise<void> {
  const resp = await request(url);
  const buffer = await resp.arrayBuffer();
  await Bun.write(outputPath, buffer);
  console.log(JSON.stringify({ outputPath, bytes: buffer.byteLength }));
}

function out(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}

function parseFlag(name: string): string | undefined {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return undefined;
  return process.argv[idx + 1];
}

function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

/** Parse a port number from argv at the given position. */
function portArg(pos: number): number {
  const val = process.argv[pos];
  if (!val) usage();
  const port = Number(val);
  if (!Number.isFinite(port) || port < 1 || port > 65535) {
    throw new Error(`Invalid port: ${val}`);
  }
  return port;
}

const command = process.argv[2];
if (!command) usage();

try {
  switch (command) {
    // ── Server commands (always on main port) ──────────────────────

    case "health": {
      out(await json(`${baseUrl(DEFAULT_PORT)}/health`));
      break;
    }

    case "launch": {
      const name = parseFlag("--name");
      const port = parseFlag("--port");
      if (!name || !port) {
        console.error("launch requires --name and --port");
        process.exit(1);
      }
      const body: Record<string, unknown> = {
        name,
        port,
        headless: hasFlag("--headless") || !hasFlag("--headed"),
      };
      out(await json(`${baseUrl(DEFAULT_PORT)}/instances/launch`, {
        method: "POST",
        body: JSON.stringify(body),
      }));
      break;
    }

    case "list-instances": {
      out(await json(`${baseUrl(DEFAULT_PORT)}/instances`));
      break;
    }

    case "stop": {
      const instanceId = process.argv[3];
      if (!instanceId) usage();
      out(await json(`${baseUrl(DEFAULT_PORT)}/instances/${instanceId}/stop`, {
        method: "POST",
      }));
      break;
    }

    // ── Instance commands (port-scoped) ────────────────────────────

    case "navigate": {
      const port = portArg(3);
      const url = process.argv[4];
      if (!url) usage();
      out(await json(`${baseUrl(port)}/navigate`, {
        method: "POST",
        body: JSON.stringify({ url }),
      }));
      break;
    }

    case "text": {
      const port = portArg(3);
      const raw = hasFlag("--raw");
      const suffix = raw ? "?raw=true" : "";
      out(await json(`${baseUrl(port)}/text${suffix}`));
      break;
    }

    case "snapshot": {
      const port = portArg(3);
      const params = new URLSearchParams();
      if (hasFlag("--interactive")) params.set("interactive", "true");
      if (hasFlag("--compact")) params.set("compact", "true");
      const suffix = params.size ? `?${params}` : "";
      out(await json(`${baseUrl(port)}/snapshot${suffix}`));
      break;
    }

    case "click":
    case "type":
    case "fill": {
      const port = portArg(3);
      const ref = process.argv[4];
      const text = process.argv.slice(5).join(" ");
      if (!ref) usage();

      const body: Record<string, string> = { kind: command, ref };
      if ((command === "type" || command === "fill") && !text) usage();
      if (text) body.text = text;

      out(await json(`${baseUrl(port)}/action`, {
        method: "POST",
        body: JSON.stringify(body),
      }));
      break;
    }

    case "eval": {
      const port = portArg(3);
      const expression = process.argv.slice(4).join(" ");
      if (!expression) usage();
      out(await json(`${baseUrl(port)}/evaluate`, {
        method: "POST",
        body: JSON.stringify({ expression }),
      }));
      break;
    }

    case "screenshot": {
      const port = portArg(3);
      const outputPath = process.argv[4] || "/tmp/pinchtab-screenshot.jpg";
      await writeBinary(`${baseUrl(port)}/screenshot?raw=true`, outputPath);
      break;
    }

    case "pdf": {
      const port = portArg(3);
      const outputPath = process.argv[4] || "/tmp/pinchtab-page.pdf";
      await writeBinary(`${baseUrl(port)}/pdf?raw=true`, outputPath);
      break;
    }

    case "tabs": {
      const port = portArg(3);
      out(await json(`${baseUrl(port)}/tabs`));
      break;
    }

    default:
      usage();
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
}
