#!/usr/bin/env bun

const BASE_URL = process.env.PINCHTAB_BASE_URL || "http://127.0.0.1:9867";

function usage(): never {
  console.error(`Usage:
  bun run scripts/pinchtab-client.ts health
  bun run scripts/pinchtab-client.ts launch [--mode headless|headed] [--profile-id <id>] [--port <port>]
  bun run scripts/pinchtab-client.ts list-instances
  bun run scripts/pinchtab-client.ts list-tabs [instanceId]
  bun run scripts/pinchtab-client.ts open <instanceId> <url>
  bun run scripts/pinchtab-client.ts navigate-tab <tabId> <url>
  bun run scripts/pinchtab-client.ts text <tabId> [--raw]
  bun run scripts/pinchtab-client.ts snapshot <tabId> [--interactive] [--compact]
  bun run scripts/pinchtab-client.ts find <tabId> <query>
  bun run scripts/pinchtab-client.ts click <tabId> <ref>
  bun run scripts/pinchtab-client.ts type <tabId> <ref> <text>
  bun run scripts/pinchtab-client.ts fill <tabId> <ref> <text>
  bun run scripts/pinchtab-client.ts eval <instanceId> <expression>
  bun run scripts/pinchtab-client.ts cookies <tabId>
  bun run scripts/pinchtab-client.ts screenshot <tabId> [path]
  bun run scripts/pinchtab-client.ts pdf <tabId> [path]
  bun run scripts/pinchtab-client.ts stop <instanceId>`);
  process.exit(1);
}

async function request(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const headers = new Headers(init?.headers);
  if (init?.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const resp = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers,
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`${resp.status} ${resp.statusText}: ${text}`);
  }

  return resp;
}

async function json(path: string, init?: RequestInit): Promise<unknown> {
  const resp = await request(path, init);
  return await resp.json();
}

async function writeBinary(path: string, outputPath: string): Promise<void> {
  const resp = await request(path);
  const buffer = await resp.arrayBuffer();
  await Bun.write(outputPath, buffer);
  console.log(JSON.stringify({ outputPath }, null, 2));
}

async function launchInstance(body: Record<string, unknown>): Promise<void> {
  const payload = JSON.stringify(body);

  try {
    const result = await json("/instances/launch", {
      method: "POST",
      body: payload,
    });
    console.log(JSON.stringify(result, null, 2));
    return;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes("404")) {
      throw error;
    }
  }

  const result = await json("/instances/start", {
    method: "POST",
    body: payload,
  });
  console.log(JSON.stringify(result, null, 2));
}

function parseFlag(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  if (index === -1) return undefined;
  return process.argv[index + 1];
}

function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

const command = process.argv[2];

if (!command) {
  usage();
}

try {
  switch (command) {
    case "health": {
      console.log(JSON.stringify(await json("/health"), null, 2));
      break;
    }

    case "launch": {
      const mode = parseFlag("--mode");
      const profileId = parseFlag("--profile-id");
      const port = parseFlag("--port");
      const body: Record<string, unknown> = {};
      if (mode) body.mode = mode;
      if (profileId) body.profileId = profileId;
      if (port) body.port = Number(port);
      await launchInstance(body);
      break;
    }

    case "list-instances": {
      console.log(JSON.stringify(await json("/instances"), null, 2));
      break;
    }

    case "list-tabs": {
      const instanceId = process.argv[3];
      const path = instanceId ? `/instances/${instanceId}/tabs` : "/tabs";
      console.log(JSON.stringify(await json(path), null, 2));
      break;
    }

    case "open": {
      const instanceId = process.argv[3];
      const url = process.argv[4];
      if (!instanceId || !url) usage();
      console.log(
        JSON.stringify(
          await json(`/instances/${instanceId}/tabs/open`, {
            method: "POST",
            body: JSON.stringify({ url }),
          }),
          null,
          2,
        ),
      );
      break;
    }

    case "navigate-tab": {
      const tabId = process.argv[3];
      const url = process.argv[4];
      if (!tabId || !url) usage();
      console.log(
        JSON.stringify(
          await json(`/tabs/${tabId}/navigate`, {
            method: "POST",
            body: JSON.stringify({ url }),
          }),
          null,
          2,
        ),
      );
      break;
    }

    case "text": {
      const tabId = process.argv[3];
      if (!tabId) usage();
      const raw = hasFlag("--raw");
      const suffix = raw ? "?raw=true" : "";
      console.log(JSON.stringify(await json(`/tabs/${tabId}/text${suffix}`), null, 2));
      break;
    }

    case "snapshot": {
      const tabId = process.argv[3];
      if (!tabId) usage();
      const params = new URLSearchParams();
      if (hasFlag("--interactive")) params.set("interactive", "true");
      if (hasFlag("--compact")) params.set("compact", "true");
      const suffix = params.size ? `?${params.toString()}` : "";
      console.log(
        JSON.stringify(await json(`/tabs/${tabId}/snapshot${suffix}`), null, 2),
      );
      break;
    }

    case "find": {
      const tabId = process.argv[3];
      const query = process.argv.slice(4).join(" ");
      if (!tabId || !query) usage();
      console.log(
        JSON.stringify(
          await json(`/tabs/${tabId}/find`, {
            method: "POST",
            body: JSON.stringify({ query }),
          }),
          null,
          2,
        ),
      );
      break;
    }

    case "click":
    case "type":
    case "fill": {
      const tabId = process.argv[3];
      const ref = process.argv[4];
      const text = process.argv.slice(5).join(" ");
      if (!tabId || !ref) usage();

      const body: Record<string, string> = { kind: command, ref };
      if ((command === "type" || command === "fill") && !text) usage();
      if (text) body.text = text;

      console.log(
        JSON.stringify(
          await json(`/tabs/${tabId}/action`, {
            method: "POST",
            body: JSON.stringify(body),
          }),
          null,
          2,
        ),
      );
      break;
    }

    case "eval": {
      const instanceId = process.argv[3];
      const expression = process.argv.slice(4).join(" ");
      if (!instanceId || !expression) usage();
      console.log(
        JSON.stringify(
          await json(`/instances/${instanceId}/evaluate`, {
            method: "POST",
            body: JSON.stringify({ expression }),
          }),
          null,
          2,
        ),
      );
      break;
    }

    case "cookies": {
      const tabId = process.argv[3];
      if (!tabId) usage();
      console.log(JSON.stringify(await json(`/tabs/${tabId}/cookies`), null, 2));
      break;
    }

    case "screenshot": {
      const tabId = process.argv[3];
      const outputPath = process.argv[4] || "/tmp/pinchtab-screenshot.jpg";
      if (!tabId) usage();
      await writeBinary(`/tabs/${tabId}/screenshot?raw=true`, outputPath);
      break;
    }

    case "pdf": {
      const tabId = process.argv[3];
      const outputPath = process.argv[4] || "/tmp/pinchtab-page.pdf";
      if (!tabId) usage();
      await writeBinary(`/tabs/${tabId}/pdf?raw=true`, outputPath);
      break;
    }

    case "stop": {
      const instanceId = process.argv[3];
      if (!instanceId) usage();
      console.log(
        JSON.stringify(
          await json(`/instances/${instanceId}/stop`, {
            method: "POST",
          }),
          null,
          2,
        ),
      );
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
