#!/bin/bash
# Wrapper script to launch the Trello MCP server with credentials.
# Reads credentials via trello-env.sh, which resolves them from (in order):
#   1. Environment variables (already set)
#   2. .env file in project root (SilverStripe 4+/5)
#   3. _ss_environment.php in project root (SilverStripe 3, PHP defines)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=trello-env.sh
. "$SCRIPT_DIR/trello-env.sh"
trello_env_load "$PROJECT_ROOT" || exit 1

for _v in TRELLO_API_KEY TRELLO_TOKEN TRELLO_BOARD_ID; do
  if [ -z "$(eval "printf '%s' \"\${$_v:-}\"")" ]; then
    echo "ERROR: $_v not set." >&2
    echo "Set it in one of: environment variables, .env, or _ss_environment.php" >&2
    exit 1
  fi
done
unset _v

# @delorenj/mcp-server-trello persists its "active board" in $HOME/.trello-mcp/config.json and
# lets that file OVERRIDE TRELLO_BOARD_ID at startup (see loadConfig() in the package's
# build/index.js — the saved boardId wins over the env-derived one whenever the file exists).
# With a shared $HOME, every project on the machine reads whichever board the most recent
# set_active_board call anywhere last wrote there: cards from one project's board silently
# surface in another, or get moved onto the wrong one. Give the server a private HOME so its
# state file is project-local, and pin the resolved board into it before every launch — this
# also makes a stray set_active_board call self-heal on the next start instead of poisoning
# sibling projects.
export npm_config_cache="${npm_config_cache:-$HOME/.npm}"
export HOME="$PROJECT_ROOT/.claude/trello-home"
mkdir -p "$HOME/.trello-mcp"
printf '{\n  "boardId": "%s"\n}\n' "$TRELLO_BOARD_ID" > "$HOME/.trello-mcp/config.json"

# HINWEIS: @delorenj/mcp-server-trello@1.8.0 deklariert im package.json ein "bin", das
# auf die rohe TypeScript-Datei src/index.ts zeigt statt auf das kompilierte build/index.js.
# Node 24 verweigert das Type-Stripping fuer .ts-Dateien unter node_modules
# (ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING), wodurch der MCP-Server sofort abstuerzt
# und der Client nur den generischen Fehler -32000 sieht. Workaround: das kompilierte
# build/index.js direkt starten, statt das kaputte bin-Skript zu nutzen. Pinned to 1.8.1
# (the first fixed release) to avoid drifting back onto 1.8.0 via "latest".
exec npx -y -p @delorenj/mcp-server-trello@1.8.1 sh -c 'NM="$(dirname "$(dirname "$(command -v mcp-server-trello)")")"; exec node "$NM/@delorenj/mcp-server-trello/build/index.js"'
