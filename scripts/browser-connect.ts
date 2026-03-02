#!/usr/bin/env bun
/**
 * Browser Automation CDP Connector
 *
 * Connects to a running Chromium via CDP using puppeteer-core.
 *
 * Usage:
 *   bun run browser-connect.ts <action> [args...]
 *
 * Actions:
 *   status              - Check CDP endpoint, list open pages
 *   screenshot [path]   - Take screenshot → /tmp/browser-screenshot.png (or custom path)
 *   url                 - Print the current page URL
 *   cookies [domain]    - Dump cookies (optionally filtered by domain)
 *   navigate <url>      - Navigate the current page to a URL
 *   html [selector]     - Get innerHTML of page or a specific selector
 *   evaluate <expr>     - Evaluate a JS expression in the page context
 */

import puppeteer, { type Browser, type Page } from "puppeteer-core";

const CDP_URL = process.env.CDP_URL || "http://127.0.0.1:9222";
const action = process.argv[2];

if (!action) {
  console.error("Usage: bun run browser-connect.ts <action> [args...]");
  console.error("Actions: status, screenshot, url, cookies, navigate, html, evaluate");
  process.exit(1);
}

async function connect(): Promise<{ browser: Browser; pages: Page[] }> {
  const browser = await puppeteer.connect({ browserURL: CDP_URL });
  const pages = await browser.pages();
  return { browser, pages };
}

async function main() {
  switch (action) {
    case "status": {
      const resp = await fetch(`${CDP_URL}/json/version`);
      const info = (await resp.json()) as Record<string, string>;
      console.log(`CDP endpoint: ${CDP_URL}`);
      console.log(`Browser: ${info["Browser"]}`);

      const { browser, pages } = await connect();
      console.log(`Open pages: ${pages.length}`);
      for (const page of pages) {
        console.log(`  - ${page.url()} (title: "${await page.title()}")`);
      }
      browser.disconnect();
      break;
    }

    case "screenshot": {
      const path = process.argv[3] || "/tmp/browser-screenshot.png";
      const { browser, pages } = await connect();
      const page = pages[0];
      if (!page) throw new Error("No pages open");
      await page.screenshot({ path, fullPage: false });
      console.log(`Screenshot saved to ${path}`);
      browser.disconnect();
      break;
    }

    case "url": {
      const { browser, pages } = await connect();
      console.log(pages[0]?.url() || "no page open");
      browser.disconnect();
      break;
    }

    case "cookies": {
      const domain = process.argv[3];
      const { browser, pages } = await connect();
      const page = pages[0];
      if (!page) throw new Error("No pages open");
      const cookies = await page.cookies();
      const filtered = domain
        ? cookies.filter((c) => c.domain.includes(domain))
        : cookies;
      console.log(JSON.stringify(filtered, null, 2));
      browser.disconnect();
      break;
    }

    case "navigate": {
      const url = process.argv[3];
      if (!url) {
        console.error("Usage: bun run browser-connect.ts navigate <url>");
        process.exit(1);
      }
      const { browser, pages } = await connect();
      const page = pages[0];
      if (!page) throw new Error("No pages open");
      await page.goto(url, { waitUntil: "domcontentloaded" });
      console.log(`Navigated to: ${page.url()}`);
      browser.disconnect();
      break;
    }

    case "html": {
      const selector = process.argv[3];
      const { browser, pages } = await connect();
      const page = pages[0];
      if (!page) throw new Error("No pages open");
      let html: string;
      if (selector) {
        const el = await page.$(selector);
        if (!el) throw new Error(`Selector not found: ${selector}`);
        html = await page.evaluate((e) => e.innerHTML, el);
      } else {
        html = await page.content();
      }
      console.log(html);
      browser.disconnect();
      break;
    }

    case "evaluate": {
      const expr = process.argv[3];
      if (!expr) {
        console.error('Usage: bun run browser-connect.ts evaluate "<expression>"');
        process.exit(1);
      }
      const { browser, pages } = await connect();
      const page = pages[0];
      if (!page) throw new Error("No pages open");
      const result = await page.evaluate(expr);
      console.log(
        typeof result === "string" ? result : JSON.stringify(result, null, 2)
      );
      browser.disconnect();
      break;
    }

    default:
      console.error(`Unknown action: ${action}`);
      console.error(
        "Valid actions: status, screenshot, url, cookies, navigate, html, evaluate"
      );
      process.exit(1);
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
