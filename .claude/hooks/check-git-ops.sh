#!/bin/bash
# Enforce git workflow rules for Bash commands:
# - git commit/merge/push on the default branch or staging: requires manual approval
# - git push --force: always blocked
# - Everything else: allowed automatically

# Resolve default branch from config, fall back to master
default_branch="master"
git_config=".claude/git-config.json"
if [[ -f "$git_config" ]]; then
  configured_branch=$(grep -o '"defaultBranch"[[:space:]]*:[[:space:]]*"[^"]*"' "$git_config" | sed 's/.*"defaultBranch"[[:space:]]*:[[:space:]]*"//;s/"$//')
  if [[ -n "$configured_branch" ]]; then
    default_branch="$configured_branch"
  fi
fi

# Read tool input from stdin
input=$(cat)

# Extract the command field from JSON input
command=$(echo "$input" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')

# If no command found, allow
if [[ -z "$command" ]]; then
  exit 0
fi

# Check for git push --force (always blocked)
if echo "$command" | grep -qE '\bgit\s+push\s+.*(-f|--force)\b'; then
  echo "⚠️ BLOCKED: Force push is not allowed."
  exit 1
fi

# For commit, merge, and push: require manual approval on default branch/staging
if echo "$command" | grep -qE '\bgit\s+(commit|merge|push)\b'; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  if [[ -z "$branch" ]]; then
    echo "⚠️ WARNING: Not in a git repository"
    exit 0
  fi

  if [[ "$branch" == "$default_branch" ]]; then
    echo "⚠️ BLOCKED: git commit/merge/push on '$branch' requires manual approval."
    echo "If you want to proceed, approve this action."
    exit 1
  fi
fi

# All other commands and branches: allow
exit 0
