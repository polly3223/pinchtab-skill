#!/usr/bin/env bun

console.error(
  "browser-connect.ts is now a compatibility wrapper. Use `bun run scripts/pinchtab-client.ts ...` instead."
);

await import("./pinchtab-client.ts");
