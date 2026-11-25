#!/usr/bin/env bash
# trello-pipeline-heartbeat.sh — hold the pipeline lock of a project while a pipeline loop runs.
#
# Usage: trello-pipeline-heartbeat.sh <project-root> [name]
#
# name = the pipeline: `trello-pipeline` (default) or `todo-pipeline`; lowercase letters and dashes.
#
# Started by the skill in the background (Bash run_in_background). It takes
# <root>/.plans/.<name>.lock with flock. For trello-pipeline this is the same lock the cron watcher
# holds for a headless run, so only one loop per project and pipeline can exist, whoever starts it
# (session, headless, second session). The two pipelines do not block each other.
#
# Output (first line, read by the skill):
#   locked <pid>   the lock is ours, the loop may start
#   busy           another loop holds the lock; exit code 3
#
# While it runs, it writes <root>/.plans/.<name>.owner ("<pid> <claudePid> <start time>") and
# touches it every 10 s, so `watch status` can show the beat age. It exits, and the kernel frees the
# lock, as soon as the Claude process that started it is gone or the owner file was deleted (the
# skill's stop signal). The lock needs no clock, so a sleeping WSL VM does not make it stale.

set -euo pipefail

BEAT_SECONDS="${TRELLO_PIPELINE_HEARTBEAT_SECONDS:-10}"

usage() { echo "Usage: $(basename "$0") <project-root> [name]" >&2; exit 1; }
{ [ "$#" -ge 1 ] && [ "$#" -le 2 ] && [ -d "$1" ]; } || usage
NAME="${2:-trello-pipeline}"
[[ "$NAME" =~ ^[a-z][a-z-]*$ ]] || { echo "Error: bad pipeline name: $NAME" >&2; exit 1; }
ROOT="$(cd "$1" && pwd)"
PLANS="$ROOT/.plans"
LOCK="$PLANS/.$NAME.lock"
OWNER="$PLANS/.$NAME.owner"
mkdir -p "$PLANS"

# find_claude_pid — the nearest ancestor process named `claude`; else the parent of this script.
# A test can set TRELLO_PIPELINE_HEARTBEAT_WATCH_PID to watch another process.
find_claude_pid() {
  if [ -n "${TRELLO_PIPELINE_HEARTBEAT_WATCH_PID:-}" ]; then
    echo "$TRELLO_PIPELINE_HEARTBEAT_WATCH_PID"
    return 0
  fi
  local pid="$PPID" comm
  while [ "$pid" -gt 1 ]; do
    comm="$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')" || break
    [ "$comm" = "claude" ] && { echo "$pid"; return 0; }
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" || break
    [ -n "$pid" ] || break
  done
  echo "$PPID"
}

CLAUDE_PID="$(find_claude_pid)"

exec 9>"$LOCK"
if ! flock -n 9; then
  echo "busy"
  exit 3
fi

# Only the lock holder may remove the owner file; the trap runs on every exit path.
trap 'rm -f "$OWNER"' EXIT
trap 'exit 0' TERM INT HUP

printf '%s %s %s\n' "$$" "$CLAUDE_PID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OWNER"
echo "locked $$"

while kill -0 "$CLAUDE_PID" 2>/dev/null && [ -f "$OWNER" ]; do
  touch "$OWNER"
  sleep "$BEAT_SECONDS" 9>&- &
  wait $! || true
done
