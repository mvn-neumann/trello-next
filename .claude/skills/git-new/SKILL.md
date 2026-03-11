---
name: git-new
description: Prepare git branch for file changes. Resolves default branch from .claude/git-config.json (auto-detects if missing). Use when the user wants to create, update, fix, add, or make something.
---

# Git New

This skill ensures you follow the project's git workflow before making any file changes.

## Usage

```
/git-new
```

## Instructions

This skill automates the git workflow checks required before making any file changes in the project.

### What This Skill Does

0. **Resolves Default Branch**: Reads from `.claude/git-config.json`, auto-detects if missing, and saves the result
1. **Checks Current Branch**: Verifies if you're on a `fix-*` or `feature-*` branch
2. **Branch Validation**: Ensures you're not on the main branch (e.g. `master` or `staging`)
3. **Guided Branch Creation**: If needed, helps create a properly named branch from the default branch

### Workflow Steps

#### Step 0: Resolve Default Branch

1. Check if `.claude/git-config.json` exists and has a `defaultBranch` value — use it.
2. If the user explicitly asks to change the default branch (e.g. "change default branch", "wrong branch", "set default branch to X"), update `.claude/git-config.json` with the new value and confirm.
3. If the config file doesn't exist, auto-detect:
   a. Run: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`
   b. If that fails, check: does `origin/main` exist? (`git rev-parse --verify origin/main 2>/dev/null`) Then try `origin/master`.
   c. If detected, ask the user to confirm: "Detected default branch: `<branch>`. Is this correct? (Yes / No, it's: ___)"
   d. If auto-detection fails entirely, ask with AskUserQuestion: "What is the default branch for this project?" (free text)
4. Write the result to `.claude/git-config.json`:
   ```json
   {
     "defaultBranch": "<branch>"
   }
   ```
5. Confirm: "Saved default branch `<branch>` to `.claude/git-config.json`. You can change it anytime by saying 'change default branch'."

Use the resolved value as `<defaultBranch>` throughout all subsequent steps.

#### Step 1: Check Current Branch

First, check what branch you're currently on:

```bash
git branch --show-current
```

#### Step 2: Validate Branch Name

The branch name MUST match one of these patterns:
- **Fix branches**: `fix-{description}` (e.g., `fix-mobile-navigation`, `fix-login-bug`)
- **Feature branches**: `feature-{description}` (e.g., `feature-user-dashboard`, `feature-dark-mode`)

If the current branch is the default branch (`<defaultBranch>`), or doesn't match the pattern, proceed to Step 3.

#### Step 3: Create New Branch (If Needed)

If you're not on a valid fix/feature branch, create one:

```bash
# Fetch latest changes
git fetch origin

# Create new branch from the default branch with --no-track
git checkout -b {branch-name} origin/<defaultBranch> --no-track
```

**Branch Naming Conventions:**

For **bug fixes** or **corrections**:
- Format: `fix-{what-to-fix}`
- Examples: `fix-mobile-navigation`, `fix-login-bug`, `fix-footer-padding`

For **new features** or **enhancements**:
- Format: `feature-{what-feature}`
- Examples: `feature-user-dashboard`, `feature-dark-mode`, `feature-email-notifications`

**Why `--no-track`?**

The `--no-track` flag prevents the feature branch from tracking the default branch. This ensures:
- Complete isolation from the default branch
- No automatic merge tracking
- Prevents accidental syncing with upstream changes

### Rules While On a Fix/Feature Branch

Once on a valid branch, follow these rules:

1. **NEVER** commit directly to the default branch (`<defaultBranch>`)
2. **NEVER** merge, rebase, or sync with the default branch while working on the branch
3. **NEVER** run `git pull` or `git fetch && git merge` to update from the default branch
4. **Every `git merge` requires explicit manual approval** — hooks will block it
5. Stay on the current branch and only commit changes related to the fix/feature
6. Only push the branch when explicitly asked to

> **Note:** These rules are enforced automatically by pre-tool hooks (`check-branch.sh` and `check-git-ops.sh`) if configured.

### Example Workflow

```bash
# 1. Check where you are
$ git branch --show-current
master

# 2. Fetch latest
$ git fetch origin

# 3. Create descriptive branch
$ git checkout -b fix-responsive-images origin/master --no-track
Switched to a new branch 'fix-responsive-images'

# 4. Verify you're on the new branch
$ git branch --show-current
fix-responsive-images

# Now you can safely make file changes
```

### FAQ

**Q: How do I change the default branch?**
A: Say "change default branch" at any time. The skill will update `.claude/git-config.json` with the new value.
