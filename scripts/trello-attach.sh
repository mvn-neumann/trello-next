#!/usr/bin/env bash
# trello-attach.sh — Upload a local file as a Trello card attachment (multipart, not via MCP).
#
# Usage: trello-attach.sh <card-id> <file-path> [attachment-name] [--replace]
#
#   attachment-name  display name (default: basename of the file)
#   --replace        after the upload, delete every other attachment of the card with the same
#                    name, so exactly one of that name remains (used for plan files)
#
# Credentials (TRELLO_API_KEY / TRELLO_TOKEN) come from trello-env.sh: environment first, then the
# project's .env. The project root is resolved as described below the header (TRELLO_PROJECT_ROOT, the
# script's own location under <root>/.claude/scripts, else the cwd).
# They travel in an Authorization header (via a curl config on stdin), never in the URL or argv.
#
# On success prints the new attachment id to stdout and exits 0; on failure prints an error to
# stderr and exits 1.

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

usage() {
  echo "Usage: $(basename "$0") <card-id> <file-path> [attachment-name] [--replace]" >&2
  exit 1
}

REPLACE=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --replace) REPLACE=1 ;;
    *)         POSITIONAL+=("$arg") ;;
  esac
done
{ [ "${#POSITIONAL[@]}" -ge 2 ] && [ "${#POSITIONAL[@]}" -le 3 ]; } || usage

CARD_ID="${POSITIONAL[0]}"
FILE="${POSITIONAL[1]}"
NAME="${POSITIONAL[2]:-$(basename "$FILE")}"

if [ ! -f "$FILE" ]; then
  echo "Error: file not found: $FILE" >&2
  exit 1
fi

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

ext="${FILE##*.}"
case "${ext,,}" in
  jpg|jpeg) MIME="image/jpeg" ;;
  png)      MIME="image/png" ;;
  gif)      MIME="image/gif" ;;
  webp)     MIME="image/webp" ;;
  pdf)      MIME="application/pdf" ;;
  md)       MIME="text/markdown" ;;
  txt)      MIME="text/plain" ;;
  json)     MIME="application/json" ;;
  *)        MIME="application/octet-stream" ;;
esac

RESPONSE=$(tcurl -X POST "$API/cards/$CARD_ID/attachments" \
  -F "name=$NAME" \
  -F "file=@${FILE};type=${MIME}" 2>&1) || {
  echo "Error: Trello API request failed." >&2
  echo "$RESPONSE" >&2
  exit 1
}

ATTACHMENT_ID=$(printf '%s' "$RESPONSE" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)
if [ -z "$ATTACHMENT_ID" ]; then
  echo "Error: upload succeeded but could not parse attachment ID from response." >&2
  echo "$RESPONSE" >&2
  exit 1
fi

if [ "$REPLACE" -eq 1 ]; then
  LISTING=$(tcurl "$API/cards/$CARD_ID/attachments?fields=id,name" 2>&1) || {
    echo "Error: uploaded $ATTACHMENT_ID, but listing the card's attachments failed." >&2
    echo "$LISTING" >&2
    exit 1
  }
  OLD_IDS=$(printf '%s' "$LISTING" | python3 -I -c '
import json, sys
name, keep = sys.argv[1], sys.argv[2]
for a in json.load(sys.stdin):
    if a.get("name") == name and a.get("id") != keep:
        print(a["id"])
' "$NAME" "$ATTACHMENT_ID")
  for old in $OLD_IDS; do
    tcurl -X DELETE "$API/cards/$CARD_ID/attachments/$old" >/dev/null 2>&1 || {
      echo "Error: uploaded $ATTACHMENT_ID, but deleting the old attachment $old failed." >&2
      exit 1
    }
  done
fi

echo "$ATTACHMENT_ID"
