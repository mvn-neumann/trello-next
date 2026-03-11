#!/usr/bin/env bash
# install.sh — Install trello-next skill, dependent skills, and launcher script.
#
# Installs to:
#   ~/.claude/skills/trello-next/SKILL.md   (shared, all projects)
#   ~/.claude/skills/git-new/SKILL.md       (shared, all projects)
#   ~/.claude/skills/git-done/SKILL.md      (shared, all projects)
#   ~/.claude/scripts/trello-mcp.sh         (shared MCP launcher)
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
mkdir -p "$CLAUDE_DIR/scripts"

# Copy skill files
cp "$SCRIPT_DIR/skills/trello-next/SKILL.md" "$CLAUDE_DIR/skills/trello-next/SKILL.md"
cp "$SCRIPT_DIR/skills/git-new/SKILL.md" "$CLAUDE_DIR/skills/git-new/SKILL.md"
cp "$SCRIPT_DIR/skills/git-done/SKILL.md" "$CLAUDE_DIR/skills/git-done/SKILL.md"

# Copy launcher script
cp "$SCRIPT_DIR/scripts/trello-mcp.sh" "$CLAUDE_DIR/scripts/trello-mcp.sh"
chmod +x "$CLAUDE_DIR/scripts/trello-mcp.sh"

echo "trello-next installed successfully."
echo ""
echo "Installed files:"
echo "  ~/.claude/skills/trello-next/SKILL.md"
echo "  ~/.claude/skills/git-new/SKILL.md"
echo "  ~/.claude/skills/git-done/SKILL.md"
echo "  ~/.claude/scripts/trello-mcp.sh"
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
echo "Usage: /trello-next"
