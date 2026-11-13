#!/usr/bin/env node
// qa-shot.mjs — one screenshot with real device emulation, for /qa-report.
// Installed to ~/.claude/tools/qa-shot/ by scripts/install-browser-tools.sh.
//
//   node qa-shot.mjs --url <url> --out <file.png> (--device "iPhone 15" | --viewport 1280x900)
//                    [--annotate '<json>'] [--wait <ms>] [--full-page]
//
// --annotate  JSON array of { selector, label, note }: stroke-only rectangle + label
//             around each element (same overlay as the skill's Option A, step 3).
// Prints one JSON line: final URL, innerWidth/innerHeight, devicePixelRatio, touch,
// annotations found/missing, requests that failed or returned >= 400.
import { chromium, devices } from 'playwright';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { homedir } from 'node:os';

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const flag = (name) => args.includes(`--${name}`);

const url = opt('url');
const out = opt('out');
if (!url || !out) {
  console.error('usage: qa-shot.mjs --url <url> --out <file.png> (--device "iPhone 15" | --viewport 1280x900) [--annotate <json>] [--wait <ms>] [--full-page]');
  process.exit(2);
}

const contextOptions = {};
const deviceName = opt('device');
if (deviceName) {
  if (!devices[deviceName]) {
    console.error(`unknown device "${deviceName}"; examples: ${Object.keys(devices).filter((n) => !n.includes('landscape')).slice(0, 8).join(', ')}`);
    process.exit(2);
  }
  Object.assign(contextOptions, devices[deviceName]);
} else {
  const [w, h] = (opt('viewport', '1280x900')).split('x').map(Number);
  Object.assign(contextOptions, { viewport: { width: w, height: h }, deviceScaleFactor: 1 });
}

const annotations = JSON.parse(opt('annotate', '[]'));
const wait = Number(opt('wait', '2500'));

const link = resolve(homedir(), '.claude/tools/chromium');
const browser = await chromium.launch({
  headless: true,
  ...(existsSync(link) ? { executablePath: link } : {}),
});
const context = await browser.newContext(contextOptions);
const page = await context.newPage();

const failed = [];
page.on('response', (r) => { if (r.status() >= 400) failed.push({ status: r.status(), url: r.url() }); });
page.on('requestfailed', (r) => failed.push({ status: 0, url: r.url(), error: r.failure()?.errorText }));

await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(wait);

// Step 3.5: close overlays before the shot
await page.evaluate(() => {
  for (const sel of ['#accept-cookies', '.cookie-accept', '[data-cookie-accept]', '.cc-allow', '#CybotCookiebotDialogBodyButtonAccept']) {
    const b = document.querySelector(sel);
    if (b) { b.click(); break; }
  }
  document.querySelectorAll(
    '[id*="debugbar"], [class*="debugbar"], .phpdebugbar, #CybotCookiebotDialog, .cc-window, ' +
    '[id*="cookie-consent"], [class*="cookie-notice"], [role="dialog"], .modal.show, .modal-backdrop',
  ).forEach((el) => { el.style.display = 'none'; });
  window.scrollTo({ top: 0, behavior: 'instant' });
});

let marked = { found: [], missing: [] };
if (annotations.length) {
  marked = await page.evaluate((list) => {
    const ns = 'http://www.w3.org/2000/svg';
    document.getElementById('__qa_anno')?.remove();
    const svg = document.createElementNS(ns, 'svg');
    svg.id = '__qa_anno';
    Object.assign(svg.style, { position: 'fixed', inset: '0', width: '100%', height: '100%', zIndex: 2147483647, pointerEvents: 'none' });
    const found = []; const missing = [];
    for (const a of list) {
      const el = document.querySelector(a.selector);
      if (!el) { missing.push(a.selector); continue; }
      found.push(a.selector);
      const r = el.getBoundingClientRect();
      // keep the frame inside the viewport so a full-screen element is still visible
      const x = Math.max(r.x - 4, 3); const y = Math.max(r.y - 4, 3);
      const w = Math.min(r.right + 4, innerWidth - 3) - x; const h = Math.min(r.bottom + 4, innerHeight - 3) - y;
      const rect = document.createElementNS(ns, 'rect');
      for (const [k, v] of Object.entries({ x, y, width: w, height: h, fill: 'none', stroke: '#e11', 'stroke-width': 3 })) rect.setAttribute(k, v);
      svg.appendChild(rect);
      const t = document.createElementNS(ns, 'text');
      for (const [k, v] of Object.entries({ x: x + 8, y: y + 26, fill: '#e11', 'font-size': 22, 'font-weight': 700 })) t.setAttribute(k, v);
      t.textContent = a.label;
      svg.appendChild(t);
    }
    document.body.appendChild(svg);
    return { found, missing };
  }, annotations);
}

mkdirSync(dirname(resolve(out)), { recursive: true });
await page.screenshot({ path: out, fullPage: flag('full-page') });

const info = await page.evaluate(() => ({
  url: location.href,
  innerWidth, innerHeight,
  devicePixelRatio,
  touch: navigator.maxTouchPoints > 0,
  userAgent: navigator.userAgent.slice(0, 80),
}));
console.log(JSON.stringify({ ...info, out, annotations: marked, failedRequests: failed }));
await browser.close();
