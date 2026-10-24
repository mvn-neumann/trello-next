#!/usr/bin/env bash
# trello-pipeline-watch.sh — start /trello-pipeline headless from cron when a card needs it.
#
# Usage: trello-pipeline-watch.sh <on|off|status|run> <project-root>
#
#   on      add this project's crontab line (every 5 min `run`); running it twice adds nothing
#   off     remove exactly this project's crontab line (tagged "# trello-pipeline-watch <root>")
#   status  on/off, lastTickAt of the state file, last log lines
#   run     the cron step: cheap checks, and only if a card needs the pipeline start
#           `claude -p "/trello-pipeline"` (TRELLO_PIPELINE_HEADLESS=1) while holding the lock
#
# `run` starts the pipeline when, with no pipeline running (lock free, lastTickAt older than
# TRELLO_PIPELINE_WATCH_STALE_MIN, default 20 min):
#   - a blocked card (Blockiert label on Trello) or a card with autoDecideCommentId has a comment
#     without the bot marker that is newer than the reference (bot comment / label added), or
#   - a card is ready: in the review list, or in todo/inProgress without the label and all
#     dependsOn cards in the done list.
# Trello wins over the state file; the script never writes the state file. When every card
# (index card included) is in the done list, `run` turns the watcher off.
#
# Files (per project, in <root>/.plans/): .trello-pipeline.lock, .trello-pipeline-watch.log,
# .trello-pipeline-watch.last (last decision, to keep the log short), .trello-pipeline-watch-run.json
# (JSON output of the last headless run).
#
# Test switches: TRELLO_PIPELINE_WATCH_DRY=1 prints the decision and never starts claude or
# changes the crontab; TRELLO_PIPELINE_WATCH_FAKE=<json> reads the board from a file instead of
# Trello ({"cards": [...], "actions": {"<cardId>": [...]}}); TRELLO_PIPELINE_WATCH_CRONTAB=<cmd>
# replaces the crontab command; TRELLO_PIPELINE_WATCH_CLAUDE=<path> replaces the claude binary.

set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CRONTAB="${TRELLO_PIPELINE_WATCH_CRONTAB:-crontab}"

usage() {
  echo "Usage: $(basename "$0") <on|off|status|run> <project-root>" >&2
  exit 1
}

[ "$#" -eq 2 ] || usage
MODE="$1"
[ -d "$2" ] || { echo "Error: not a directory: $2" >&2; exit 1; }
ROOT="$(cd "$2" && pwd)"
# cron treats % as a newline and the line is not quoted, so only allow plain path characters.
[[ "$ROOT" =~ ^[A-Za-z0-9_./-]+$ ]] || { echo "Error: project path has characters cron cannot take: $ROOT" >&2; exit 1; }

MARKER="# trello-pipeline-watch $ROOT"
CRON_LINE="*/5 * * * * $SCRIPT_PATH run $ROOT $MARKER"
PLANS="$ROOT/.plans"
STATE="$PLANS/.trello-pipeline.json"
LOG="$PLANS/.trello-pipeline-watch.log"
LAST="$PLANS/.trello-pipeline-watch.last"
DRY="${TRELLO_PIPELINE_WATCH_DRY:-0}"

log() {
  [ -d "$PLANS" ] || return 0
  printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"
}

# crontab_without_mine — current crontab minus this project's line (exact marker at line end).
crontab_without_mine() {
  { "$CRONTAB" -l 2>/dev/null || true; } | awk -v m="$MARKER" \
    'length($0) < length(m) || substr($0, length($0) - length(m) + 1) != m'
}

is_on() {
  { "$CRONTAB" -l 2>/dev/null || true; } | awk -v m="$MARKER" \
    'length($0) >= length(m) && substr($0, length($0) - length(m) + 1) == m { found = 1 } END { exit !found }'
}

watch_on() {
  if is_on; then
    echo "Watcher already on for $ROOT"
    return 0
  fi
  # Read the whole crontab before writing it back, never in one pipe with the install.
  local rest
  rest="$(crontab_without_mine)"
  { [ -n "$rest" ] && printf '%s\n' "$rest"; echo "$CRON_LINE"; } | "$CRONTAB" -
  log "Watcher an"
  echo "Watcher on for $ROOT"
}

watch_off() {
  if ! is_on; then
    echo "Watcher already off for $ROOT"
    return 0
  fi
  local rest
  rest="$(crontab_without_mine)"
  if [ -n "$rest" ]; then printf '%s\n' "$rest" | "$CRONTAB" -; else "$CRONTAB" -r; fi
  log "Watcher aus${1:+ — $1}"
  echo "Watcher off for $ROOT"
}

watch_status() {
  if is_on; then echo "Watcher: on"; else echo "Watcher: off"; fi
  if [ -f "$STATE" ]; then
    python3 -I -c 'import json,sys; print("lastTickAt:", json.load(open(sys.argv[1])).get("lastTickAt") or "–")' "$STATE"
  else
    echo "No state file: $STATE"
  fi
  [ -f "$LOG" ] && { echo "Last log lines:"; tail -n 5 "$LOG"; }
  return 0
}

# decide — prints one line "start|skip|off <reason>", then one line per state/Trello difference.
# Runs in a subshell: trello-env.sh exports the whole project .env, which must not reach claude.
decide() {
  (
    if [ -z "${TRELLO_PIPELINE_WATCH_FAKE:-}" ]; then
      # shellcheck source=trello-env.sh
      . "$SCRIPT_DIR/trello-env.sh"
      trello_env_load "$ROOT" >/dev/null || exit 1
    fi
    python3 -I - "$STATE" <<'PY'
import datetime, json, os, sys, urllib.request

BOT = "🤖 trello-pipeline ·"
state = json.load(open(sys.argv[1], encoding="utf-8"))
stale_min = int(os.environ.get("TRELLO_PIPELINE_WATCH_STALE_MIN", "20"))
fake = os.environ.get("TRELLO_PIPELINE_WATCH_FAKE")
fake = json.load(open(fake, encoding="utf-8")) if fake else None

def get(path):
    req = urllib.request.Request("https://api.trello.com/1" + path, headers={"Authorization":
        'OAuth oauth_consumer_key="%s", oauth_token="%s"' % (os.environ["TRELLO_API_KEY"], os.environ["TRELLO_TOKEN"])})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def actions(card_id):
    if fake is not None:
        return fake.get("actions", {}).get(card_id, [])
    return get(f"/cards/{card_id}/actions?filter=commentCard,addLabelToCard&limit=200")

tick = state.get("lastTickAt")
if tick:
    age = datetime.datetime.now(datetime.timezone.utc) - datetime.datetime.fromisoformat(tick.replace("Z", "+00:00"))
    if age < datetime.timedelta(minutes=stale_min):
        print(f"skip Pipeline läuft (lastTickAt {tick})")
        sys.exit(0)

board = fake["cards"] if fake is not None else get(f"/boards/{state['boardIdLong']}/cards?fields=idList,idLabels,name")
by_id = {c["id"]: c for c in board}
role_of = {v: k for k, v in state["lists"].items()}
label = state["blockedLabelId"]
cards = state["cards"]

def role(nn):
    c = by_id.get(cards[nn]["cardId"])
    return role_of.get(c["idList"]) if c else None

def blocked(nn):
    c = by_id.get(cards[nn]["cardId"])
    return bool(c) and label in c.get("idLabels", [])

diffs = []
for nn, s in sorted(cards.items()):
    r = role(nn)
    if r is None:
        diffs.append(f"{nn}: Karte nicht auf dem Board")
        continue
    if blocked(nn) != (s["status"] == "blocked"):
        diffs.append(f"{nn}: Status {s['status']}, Trello {'Blockiert' if blocked(nn) else 'ohne Label'}")
    if (r == "done") != (s["status"] == "done"):
        diffs.append(f"{nn}: Status {s['status']}, Trello-Liste {r}")

index = by_id.get(state.get("indexCardId") or "")
if all(role(nn) == "done" for nn in cards):
    if index is None or role_of.get(index["idList"]) == "done":
        print("off alle Karten Fertig")
    else:
        print("start alle Aufgaben Fertig, Indexkarte abschließen")
    sys.exit(0)

def new_comment(nn, ref_id):
    acts = actions(cards[nn]["cardId"])
    refs = [a["date"] for a in acts if a["id"] == ref_id]
    if blocked(nn):
        refs += [a["date"] for a in acts if a["type"] == "addLabelToCard"
                 and a.get("data", {}).get("label", {}).get("id") == label]
    if not refs:
        return False
    ref = max(refs)
    return any(a["type"] == "commentCard" and a["date"] > ref
               and not a.get("data", {}).get("text", "").startswith(BOT) for a in acts)

reason = None
for nn, s in sorted(cards.items()):
    if role(nn) in (None, "done"):
        continue
    if blocked(nn) and new_comment(nn, s.get("blockCommentId")):
        reason = f"{nn} neuer Kommentar auf blockierter Karte"
    elif s.get("autoDecideCommentId") and new_comment(nn, s["autoDecideCommentId"]):
        reason = f"{nn} Veto-Kommentar"
    elif not blocked(nn) and (role(nn) == "review" or (role(nn) in ("todo", "inProgress")
            and all(d in cards and role(d) == "done" for d in s.get("dependsOn", [])))):
        reason = f"{nn} bereit (Liste {role(nn)})"
    if reason:
        break

print(f"start {reason}" if reason else "skip nichts zu tun")
for d in diffs:
    print(d)
PY
  )
}

watch_run() {
  [ -f "$STATE" ] || exit 0
  exec 9>"$PLANS/.trello-pipeline.lock"
  flock -n 9 || exit 0

  local out
  if ! out="$(decide 2>&1)"; then
    log "Fehler bei der Prüfung: $(printf '%s' "$out" | tail -n 3 | tr '\n' ' ')"
    [ "$DRY" = 1 ] && echo "error: $out"
    exit 1
  fi
  local decision="${out%%$'\n'*}"

  if [ "$DRY" = 1 ]; then
    printf '%s\n' "$out"
    exit 0
  fi

  # Log only when the decision changed, so a quiet board does not grow the log every 5 minutes.
  if [ "$out" != "$(cat "$LAST" 2>/dev/null || true)" ]; then
    while IFS= read -r line; do log "$line"; done <<< "$out"
    printf '%s' "$out" > "$LAST"
  fi

  case "$decision" in
    off*)   watch_off "${decision#off }" >/dev/null ;;
    start*)
      log "claude -p /trello-pipeline gestartet (${decision#start })"
      local rc=0
      # Clean environment: no ANTHROPIC_API_KEY (would switch to API billing), no variables of a
      # calling Claude session. 9>&- so processes that outlive the run (ddev, mutagen) do not
      # keep the lock; this script holds it until claude returns.
      ( cd "$ROOT" && env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}" \
          PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" LANG=C.UTF-8 \
          XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
          CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 TRELLO_PIPELINE_HEADLESS=1 \
          timeout "${TRELLO_PIPELINE_WATCH_TIMEOUT:-12h}" \
          "${TRELLO_PIPELINE_WATCH_CLAUDE:-claude}" -p "/trello-pipeline" --permission-mode bypassPermissions --output-format json \
          > "$PLANS/.trello-pipeline-watch-run.json" 2>>"$LOG" 9>&- ) || rc=$?
      local cost
      cost="$(python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("total_cost_usd", "?"))
except Exception: print("?")' "$PLANS/.trello-pipeline-watch-run.json")"
      log "claude beendet: Exit $rc, Kosten \$$cost"
      rm -f "$LAST"
      ;;
  esac
}

case "$MODE" in
  on)     [ "$DRY" = 1 ] && { echo "dry: would add: $CRON_LINE"; exit 0; }; watch_on ;;
  off)    [ "$DRY" = 1 ] && { echo "dry: would remove the line with: $MARKER"; exit 0; }; watch_off ;;
  status) watch_status ;;
  run)    watch_run ;;
  *)      usage ;;
esac
