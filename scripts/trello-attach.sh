#!/usr/bin/env bash
# trello-attach.sh — Upload a local file as a Trello card attachment.
#
# Usage: trello-attach.sh <card-id> <file-path> [attachment-name]
#
# Reads TRELLO_API_KEY and TRELLO_TOKEN from (in order):
#   1. Environment variables
#   2. .env in the current working directory
#   3. _ss_environment.php in the current working directory
#
# On success, prints the attachment ID to stdout and exits 0.
# On failure, prints an error message to stderr and exits 1.

set -euo pipefail

# ── Usage check ────────────────────────────────────────────────────────────────
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $(basename "$0") <card-id> <file-path> [attachment-name]" >&2
  echo "" >&2
  echo "  card-id         Trello card ID (from card URL or trello-active-card.json)" >&2
  echo "  file-path       Local file to upload (jpg, png, gif, webp, pdf, …)" >&2
  echo "  attachment-name Optional display name (default: basename of file)" >&2
  exit 1
fi

CARD_ID="$1"
FILE="$2"
NAME="${3:-$(basename "$FILE")}"

if [ ! -f "$FILE" ]; then
  echo "Error: file not found: $FILE" >&2
  exit 1
fi

# ── Credential resolution ──────────────────────────────────────────────────────
# 1. Environment variables (already set — no action needed)
# 2. .env in $PWD
if [ -f ".env" ]; then
  set -a
  # shellcheck source=/dev/null
  source ".env"
  set +a
fi

# 3. _ss_environment.php in $PWD
if [ -z "${TRELLO_API_KEY:-}" ] || [ -z "${TRELLO_TOKEN:-}" ]; then
  if [ -f "_ss_environment.php" ]; then
    extract_define() { grep -oP "define\('$1',\s*'\K[^']+" "_ss_environment.php" 2>/dev/null || true; }
    [ -z "${TRELLO_API_KEY:-}" ] && TRELLO_API_KEY="$(extract_define TRELLO_API_KEY)"
    [ -z "${TRELLO_TOKEN:-}" ]   && TRELLO_TOKEN="$(extract_define TRELLO_TOKEN)"
  fi
fi

if [ -z "${TRELLO_API_KEY:-}" ] || [ -z "${TRELLO_TOKEN:-}" ]; then
  echo "Error: TRELLO_API_KEY and TRELLO_TOKEN must be set." >&2
  echo "Set them in one of: environment variables, .env, or _ss_environment.php" >&2
  exit 1
fi

# ── MIME type detection ────────────────────────────────────────────────────────
ext="${FILE##*.}"
case "${ext,,}" in
  jpg|jpeg) MIME="image/jpeg" ;;
  png)      MIME="image/png" ;;
  gif)      MIME="image/gif" ;;
  webp)     MIME="image/webp" ;;
  pdf)      MIME="application/pdf" ;;
  *)        MIME="application/octet-stream" ;;
esac

# ── Upload ─────────────────────────────────────────────────────────────────────
RESPONSE=$(curl -sf -X POST \
  "https://api.trello.com/1/cards/${CARD_ID}/attachments?key=${TRELLO_API_KEY}&token=${TRELLO_TOKEN}" \
  -F "name=${NAME}" \
  -F "file=@${FILE};type=${MIME}" \
  2>&1) || {
  echo "Error: Trello API request failed." >&2
  echo "$RESPONSE" >&2
  exit 1
}

# Extract id from JSON response (no jq dependency)
ATTACHMENT_ID=$(echo "$RESPONSE" | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)
if [ -z "$ATTACHMENT_ID" ]; then
  echo "Error: upload succeeded but could not parse attachment ID from response." >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "$ATTACHMENT_ID"
