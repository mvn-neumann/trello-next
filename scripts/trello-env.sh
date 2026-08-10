#!/usr/bin/env bash
# trello-env.sh — resolve TRELLO_API_KEY / TRELLO_TOKEN / TRELLO_BOARD_ID for a project.
#
# Single source of truth for the credential lookup, shared by trello-mcp.sh (the MCP launcher)
# and any skill that needs to know the project's board id outside of a running server
# (trello-next, git-done, monthly-report). Meant to be sourced, not executed:
#   . "$SCRIPT_DIR/trello-env.sh"
#   trello_env_load "$PROJECT_ROOT" || exit 1
#
# Detection is by env-file presence, which maps 1:1 onto the SilverStripe version:
#   SilverStripe 4+/5 (vendor/silverstripe/, no framework/) -> .env               KEY="value"
#   SilverStripe 3    (framework/)                          -> _ss_environment.php  define('KEY', 'value')
# No project on this machine has both files, so presence alone disambiguates. If that ever stops
# holding, switch the discriminator to `[ -d "$root/framework" ]` vs `[ -d "$root/vendor/silverstripe" ]`.

# Guard against double-sourcing (harmless, but avoids redefining the function pointlessly).
if [ -n "${_TRELLO_ENV_SH:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
_TRELLO_ENV_SH=1

# trello_env_load <project-root>
# Populates TRELLO_API_KEY / TRELLO_TOKEN / TRELLO_BOARD_ID in the current shell (exported).
# Already-set environment variables always win over the project's env file.
trello_env_load() {
  local root="$1"

  if [ -f "$root/.env" ]; then
    # SilverStripe 4+/5 layout. `source` (not a KEY=VAL parser) so quoting/interpolation in the
    # file behaves the same way it does for every other tool that reads it.
    # set +u: unrelated values in these files (e.g. SSH_PASS) may contain a literal '$', which
    # nounset would treat as an unbound-variable expansion and abort before we ever read Trello.
    set -a
    set +u
    # shellcheck disable=SC1091
    . "$root/.env"
    set -u
    set +a
  elif [ -f "$root/_ss_environment.php" ]; then
    # SilverStripe 3 layout.
    local ss="$root/_ss_environment.php"
    _trello_ss_define() {
      sed -n "s/^[[:space:]]*define([[:space:]]*'$1'[[:space:]]*,[[:space:]]*'\([^']*\)'.*/\1/p" "$ss" | tail -1
    }
    [ -z "${TRELLO_API_KEY:-}"  ] && export TRELLO_API_KEY="$(_trello_ss_define TRELLO_API_KEY)"
    [ -z "${TRELLO_TOKEN:-}"    ] && export TRELLO_TOKEN="$(_trello_ss_define TRELLO_TOKEN)"
    [ -z "${TRELLO_BOARD_ID:-}" ] && export TRELLO_BOARD_ID="$(_trello_ss_define TRELLO_BOARD_ID)"
    unset -f _trello_ss_define
  else
    echo "trello-env: neither .env (SilverStripe 4+) nor _ss_environment.php (SilverStripe 3) found in $root" >&2
    return 1
  fi
}
