#!/usr/bin/env bash
# install-browser-tools.sh — browser tools for /qa-report with real device emulation.
# Idempotent; also called by install.sh. Needs node/npx and the `claude` CLI.
#
# Installs:
#   ~/.claude/tools/chromium            link to Playwright's Chromium (no system Chrome needed, e.g. WSL)
#   ~/.claude/tools/qa-shot/            Playwright script for one emulated screenshot (qa-shot.mjs)
#   MCP servers (user scope, headless, isolated profile, that Chromium):
#     playwright          desktop, 1280x900
#     playwright-mobile   --device "iPhone 15" (touch, DPR 3, mobile UA)
#     chrome-devtools     Chrome DevTools MCP (emulate, performance, network)
#
# Restart Claude Code afterwards: MCP servers load at startup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$HOME/.claude/tools"

# Pinned: bump on purpose, run this script again, then `claude mcp remove` the old entries.
PLAYWRIGHT_VERSION="1.65.0"
PLAYWRIGHT_MCP_VERSION="0.0.85"
CHROME_DEVTOOLS_MCP_VERSION="1.13.0"
DEVICE="iPhone 15"

command -v npx >/dev/null || { echo "npx not found (install Node.js)" >&2; exit 1; }
mkdir -p "$TOOLS/qa-shot"

# 1. Chromium for the pinned Playwright, and a stable link to it
echo "== Chromium (Playwright $PLAYWRIGHT_VERSION)"
npx -y "playwright@$PLAYWRIGHT_VERSION" install chromium
BROWSERS="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
CHROME="$(ls -d "$BROWSERS"/chromium-*/chrome-linux*/chrome 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$CHROME" ] && [ -x "$CHROME" ] || { echo "Chromium binary not found under $BROWSERS" >&2; exit 1; }
ln -sfn "$CHROME" "$TOOLS/chromium"
echo "   $TOOLS/chromium -> $CHROME"

# 2. Script fallback (Playwright library, no MCP)
echo "== qa-shot"
cp "$SCRIPT_DIR/qa-shot.mjs" "$TOOLS/qa-shot/qa-shot.mjs"
cat > "$TOOLS/qa-shot/package.json" <<EOF
{ "name": "qa-shot", "private": true, "type": "module", "dependencies": { "playwright": "$PLAYWRIGHT_VERSION" } }
EOF
(cd "$TOOLS/qa-shot" && npm install --silent --no-audit --no-fund)
echo "   node $TOOLS/qa-shot/qa-shot.mjs --url <url> --out <png> [--device \"$DEVICE\" | --viewport 1280x900]"

# 3. MCP servers (user scope), only when missing
add_mcp() {
  local name="$1"; shift
  if claude mcp get "$name" >/dev/null 2>&1; then
    echo "   $name: already registered"
  else
    claude mcp add --scope user "$name" -- "$@"
    echo "   $name: registered"
  fi
}
echo "== MCP servers"
command -v claude >/dev/null || { echo "claude CLI not found, skipping MCP registration" >&2; exit 0; }
add_mcp playwright npx "@playwright/mcp@$PLAYWRIGHT_MCP_VERSION" \
  --headless --isolated --executable-path "$TOOLS/chromium" --viewport-size 1280x900
add_mcp playwright-mobile npx "@playwright/mcp@$PLAYWRIGHT_MCP_VERSION" \
  --headless --isolated --executable-path "$TOOLS/chromium" --device "$DEVICE"
add_mcp chrome-devtools npx "chrome-devtools-mcp@$CHROME_DEVTOOLS_MCP_VERSION" \
  --headless --isolated -e "$TOOLS/chromium"

echo ""
echo "Done. Restart Claude Code to load the MCP tools (check with: claude mcp list)."
echo "A leftover mcpServers.playwright block in ~/.claude/settings.json is ignored by Claude Code; remove it."
