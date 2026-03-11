#!/bin/bash
# Check if current branch follows naming convention before file edits

# Resolve default branch from config, fall back to master
default_branch="master"
git_config=".claude/git-config.json"
if [[ -f "$git_config" ]]; then
  configured_branch=$(grep -o '"defaultBranch"[[:space:]]*:[[:space:]]*"[^"]*"' "$git_config" | sed 's/.*"defaultBranch"[[:space:]]*:[[:space:]]*"//;s/"$//')
  if [[ -n "$configured_branch" ]]; then
    default_branch="$configured_branch"
  fi
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [[ -z "$branch" ]]; then
  echo "⚠️ WARNING: Not in a git repository"
  exit 0
fi

if [[ "$branch" =~ ^(fix-|feature-) ]]; then
  exit 0
fi

echo "⚠️ BLOCKED: You are on branch '$branch'."
echo "You MUST create a fix-* or feature-* branch before making file changes."
echo ""
echo "Run these commands:"
echo "  git fetch origin"
echo "  git checkout -b fix-<description> origin/$default_branch --no-track"
echo ""
echo "See CLAUDE.md for Git Workflow instructions."
exit 1
