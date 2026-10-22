#!/usr/bin/env bash
# trello-attachment-get.sh — Download a Trello card attachment by name to a local file.
#
# Usage: trello-attachment-get.sh <card-id> <attachment-name> <out-file>
#
# Takes the newest attachment with that exact name. The file is written to a temp file next to
# <out-file> and moved into place only after a complete download, so a failed run never destroys
# an existing local copy. Credentials and project root as in trello-attach.sh (trello-env.sh, Authorization header).
#
# Exit codes: 0 written · 2 the card has no attachment with that name · 1 any other error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Project root: $TRELLO_PROJECT_ROOT, else <root> when this script is a copy or symlink in
# <root>/.claude/scripts, else the current directory (the globally installed ~/.claude/scripts case).
if [ -n "${TRELLO_PROJECT_ROOT:-}" ]; then
  PROJECT_ROOT="$TRELLO_PROJECT_ROOT"
else
  PROJECT_ROOT="$PWD"
  CANDIDATE="$(cd "$SCRIPT_DIR/../.." && pwd)"
  if [ "$(basename "$SCRIPT_DIR")" = "scripts" ] && [ "$(basename "$(dirname "$SCRIPT_DIR")")" = ".claude" ] \
     && [ "$CANDIDATE" != "$HOME" ]; then
    PROJECT_ROOT="$CANDIDATE"
  fi
fi
API="https://api.trello.com/1"

if [ $# -ne 3 ]; then
  echo "Usage: $(basename "$0") <card-id> <attachment-name> <out-file>" >&2
  exit 1
fi
CARD_ID="$1"
NAME="$2"
OUT="$3"

# shellcheck source=trello-env.sh
. "$SCRIPT_DIR/trello-env.sh"
trello_env_load "$PROJECT_ROOT" || exit 1
if [ -z "${TRELLO_API_KEY:-}" ] || [ -z "${TRELLO_TOKEN:-}" ]; then
  echo "Error: TRELLO_API_KEY and TRELLO_TOKEN must be set (environment or $PROJECT_ROOT/.env)." >&2
  exit 1
fi

# tcurl <curl args…> — curl against the Trello API with the OAuth header read from stdin.
tcurl() {
  printf 'header = "Authorization: OAuth oauth_consumer_key=\\"%s\\", oauth_token=\\"%s\\""\n' \
    "$TRELLO_API_KEY" "$TRELLO_TOKEN" | curl -sS --fail-with-body -K - "$@"
}

LISTING=$(tcurl "$API/cards/$CARD_ID/attachments?fields=id,name,date" 2>&1) || {
  echo "Error: could not list the attachments of card $CARD_ID." >&2
  echo "$LISTING" >&2
  exit 1
}

# Newest attachment with the exact name: prints "<id>" and, on the second line, the URL-encoded name.
PICK=$(printf '%s' "$LISTING" | python3 -I -c '
import json, sys, urllib.parse
name = sys.argv[1]
hits = [a for a in json.load(sys.stdin) if a.get("name") == name]
if hits:
    hits.sort(key=lambda a: a.get("date", ""))
    print(hits[-1]["id"])
    print(urllib.parse.quote(name, safe=""))
' "$NAME")
if [ -z "$PICK" ]; then
  echo "No attachment named '$NAME' on card $CARD_ID." >&2
  exit 2
fi
ATTACHMENT_ID=$(printf '%s\n' "$PICK" | sed -n 1p)
ENCODED_NAME=$(printf '%s\n' "$PICK" | sed -n 2p)

mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp "$OUT.XXXXXX")
trap 'rm -f "$TMP"' EXIT
if ! tcurl -L -o "$TMP" "$API/cards/$CARD_ID/attachments/$ATTACHMENT_ID/download/$ENCODED_NAME" 2>/dev/null; then
  echo "Error: download of attachment $ATTACHMENT_ID failed." >&2
  exit 1
fi
mv "$TMP" "$OUT"
trap - EXIT
