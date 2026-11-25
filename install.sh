#!/usr/bin/env bash
# install.sh — Install trello-next skill, dependent skills, and launcher script.
#
# Installs to:
#   ~/.claude/skills/trello-next/SKILL.md   (shared, all projects)
#   ~/.claude/skills/git-new/SKILL.md       (shared, all projects)
#   ~/.claude/skills/git-done/SKILL.md      (shared, all projects)
#   ~/.claude/skills/spec/SKILL.md          (shared, all projects)
#   ~/.claude/skills/tdd/SKILL.md           (shared, all projects)
#   ~/.claude/skills/trello-pipeline/SKILL.md (shared, all projects)
#   ~/.claude/scripts/trello-mcp.sh         (shared MCP launcher)
#   ~/.claude/scripts/trello-attach.sh, trello-attachment-get.sh (plan/screenshot upload and download)
#   ~/.claude/scripts/trello-pipeline-watch.sh (cron watcher: starts /trello-pipeline from a card comment)
#   ~/.claude/scripts/trello-pipeline-heartbeat.sh (holds the per-project loop lock while /trello-pipeline runs)
#
# Per-project setup (manual):
#   .mcp.json  — add the trello MCP server entry
#   .env or _ss_environment.php — add TRELLO_API_KEY, TRELLO_TOKEN, TRELLO_BOARD_ID

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# Create target directories
mkdir -p "$CLAUDE_DIR/skills/trello-next"
mkdir -p "$CLAUDE_DIR/skills/git-new"
mkdir -p "$CLAUDE_DIR/skills/git-done"
mkdir -p "$CLAUDE_DIR/skills/qa-report"
mkdir -p "$CLAUDE_DIR/skills/qa-screencast"
mkdir -p "$CLAUDE_DIR/skills/log-time"
mkdir -p "$CLAUDE_DIR/skills/spec"
mkdir -p "$CLAUDE_DIR/skills/tdd"
mkdir -p "$CLAUDE_DIR/skills/trello-pipeline"
mkdir -p "$CLAUDE_DIR/scripts"

# Copy skill files
cp "$SCRIPT_DIR/skills/trello-next/SKILL.md" "$CLAUDE_DIR/skills/trello-next/SKILL.md"
cp "$SCRIPT_DIR/skills/git-new/SKILL.md" "$CLAUDE_DIR/skills/git-new/SKILL.md"
cp "$SCRIPT_DIR/skills/git-done/SKILL.md" "$CLAUDE_DIR/skills/git-done/SKILL.md"
cp "$SCRIPT_DIR/skills/qa-report/SKILL.md" "$CLAUDE_DIR/skills/qa-report/SKILL.md"
cp "$SCRIPT_DIR/skills/qa-screencast/SKILL.md" "$CLAUDE_DIR/skills/qa-screencast/SKILL.md"
cp "$SCRIPT_DIR/skills/log-time/SKILL.md" "$CLAUDE_DIR/skills/log-time/SKILL.md"
cp "$SCRIPT_DIR/skills/spec/SKILL.md" "$CLAUDE_DIR/skills/spec/SKILL.md"
cp "$SCRIPT_DIR/skills/tdd/SKILL.md" "$CLAUDE_DIR/skills/tdd/SKILL.md"
cp "$SCRIPT_DIR/skills/trello-pipeline/SKILL.md" "$CLAUDE_DIR/skills/trello-pipeline/SKILL.md"

# Copy launcher scripts
cp "$SCRIPT_DIR/scripts/trello-env.sh" "$CLAUDE_DIR/scripts/trello-env.sh"
chmod +x "$CLAUDE_DIR/scripts/trello-env.sh"
cp "$SCRIPT_DIR/scripts/trello-mcp.sh" "$CLAUDE_DIR/scripts/trello-mcp.sh"
chmod +x "$CLAUDE_DIR/scripts/trello-mcp.sh"
cp "$SCRIPT_DIR/scripts/trello-attach.sh" "$CLAUDE_DIR/scripts/trello-attach.sh"
chmod +x "$CLAUDE_DIR/scripts/trello-attach.sh"
cp "$SCRIPT_DIR/scripts/trello-attachment-get.sh" "$CLAUDE_DIR/scripts/trello-attachment-get.sh"
chmod +x "$CLAUDE_DIR/scripts/trello-attachment-get.sh"
cp "$SCRIPT_DIR/scripts/trello-pipeline-watch.sh" "$CLAUDE_DIR/scripts/trello-pipeline-watch.sh"
chmod +x "$CLAUDE_DIR/scripts/trello-pipeline-watch.sh"
cp "$SCRIPT_DIR/scripts/trello-pipeline-heartbeat.sh" "$CLAUDE_DIR/scripts/trello-pipeline-heartbeat.sh"
chmod +x "$CLAUDE_DIR/scripts/trello-pipeline-heartbeat.sh"

# Browser tools for /qa-report (Playwright MCP, Chrome DevTools MCP, qa-shot.mjs).
# Skipped when SKIP_BROWSER_TOOLS=1 (needs node/npx, the claude CLI and a ~130 MB download).
if [ "${SKIP_BROWSER_TOOLS:-0}" != "1" ]; then
  bash "$SCRIPT_DIR/scripts/install-browser-tools.sh" || echo "Browser tools not installed (run scripts/install-browser-tools.sh later)." >&2
fi

echo "trello-next installed successfully."
echo ""
echo "Installed files:"
echo "  ~/.claude/skills/trello-next/SKILL.md"
echo "  ~/.claude/skills/git-new/SKILL.md"
echo "  ~/.claude/skills/git-done/SKILL.md"
echo "  ~/.claude/skills/qa-report/SKILL.md"
echo "  ~/.claude/skills/qa-screencast/SKILL.md"
echo "  ~/.claude/skills/log-time/SKILL.md"
echo "  ~/.claude/skills/spec/SKILL.md"
echo "  ~/.claude/skills/tdd/SKILL.md"
echo "  ~/.claude/skills/trello-pipeline/SKILL.md"
echo "  ~/.claude/scripts/trello-mcp.sh"
echo "  ~/.claude/scripts/trello-env.sh"
echo "  ~/.claude/scripts/trello-attach.sh"
echo "  ~/.claude/scripts/trello-attachment-get.sh"
echo "  ~/.claude/scripts/trello-pipeline-watch.sh"
echo "  ~/.claude/scripts/trello-pipeline-heartbeat.sh"
echo ""
echo "Per-project setup:"
echo "  1. Add Trello credentials to your project's .env or _ss_environment.php:"
echo "     TRELLO_API_KEY=<your-key>"
echo "     TRELLO_TOKEN=<your-token>"
echo "     TRELLO_BOARD_ID=<your-board-id>"
echo ""
echo "  2. Add the MCP server to your project's .mcp.json:"
echo '     "trello": { "command": "bash", "args": [".claude/scripts/trello-mcp.sh"] }'
echo ""
echo "     Or symlink the shared script into your project:"
echo "     mkdir -p .claude/scripts"
echo "     ln -sf ~/.claude/scripts/trello-mcp.sh .claude/scripts/trello-mcp.sh"
echo ""
echo "Usage: /trello-next   (one card)   ·   /trello-pipeline   (cards from .plans/NN-*.md; see README)"
