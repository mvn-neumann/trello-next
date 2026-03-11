#!/bin/bash
# Wrapper script to launch the Trello MCP server with credentials.
# Reads from multiple sources in order:
#   1. Environment variables (already set)
#   2. .env file in project root
#   3. _ss_environment.php (SilverStripe PHP defines)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source .env if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Fall back to _ss_environment.php for any missing vars
if [ -z "$TRELLO_API_KEY" ] || [ -z "$TRELLO_TOKEN" ] || [ -z "$TRELLO_BOARD_ID" ]; then
  SS_ENV="$PROJECT_ROOT/_ss_environment.php"
  if [ -f "$SS_ENV" ]; then
    extract_define() { grep -oP "define\('$1',\s*'\\K[^']+" "$SS_ENV"; }
    [ -z "$TRELLO_API_KEY" ] && export TRELLO_API_KEY="$(extract_define TRELLO_API_KEY)"
    [ -z "$TRELLO_TOKEN" ] && export TRELLO_TOKEN="$(extract_define TRELLO_TOKEN)"
    [ -z "$TRELLO_BOARD_ID" ] && export TRELLO_BOARD_ID="$(extract_define TRELLO_BOARD_ID)"
  fi
fi

if [ -z "$TRELLO_API_KEY" ] || [ -z "$TRELLO_TOKEN" ]; then
  echo "ERROR: TRELLO_API_KEY and TRELLO_TOKEN must be set." >&2
  echo "Set them in one of: environment variables, .env, or _ss_environment.php" >&2
  exit 1
fi

exec npx -y @delorenj/mcp-server-trello
