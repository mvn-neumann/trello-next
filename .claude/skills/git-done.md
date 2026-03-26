---
name: git-done
description: Merge the current fix/feature branch into the default branch and push to origin. Resolves default branch from .claude/git-config.json (auto-detects if missing).
---

# Git Done

This skill merges the current fix/feature branch into the default branch and pushes it to origin.

## Usage

```
/git-done
```

## Instructions

This skill automates the final step of the git workflow: merging your completed fix/feature branch into the default branch and pushing upstream.

### What This Skill Does

0. **Resolves Default Branch**: Reads from `.claude/git-config.json`, auto-detects if missing, and saves the result
1. **Checks Current Branch**: Confirms you're on a `fix-*` or `feature-*` branch (not the default branch)
2. **Commits Pending Changes**: Stages and commits any modified or untracked files
3. **Switches to Default Branch**: Checks out the default branch
4. **Pulls Latest**: Pulls any remote changes to the default branch
5. **Merges Branch**: Fast-forward merges the feature branch into the default branch
6. **Pushes**: Pushes the default branch to origin
7. **Advances Trello Card**: Moves the active Trello card to the next list (if state file exists)
8. **Reports Result**: Shows what was merged, pushed, and Trello status

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

```bash
git branch --show-current
```

If you are already on the default branch (`<defaultBranch>`), ask the user which branch they want to merge and skip to Step 3.

#### Step 2: Commit Pending Changes

```bash
git status
```

If there are modified or untracked files, stage and commit them:

1. **Review changes** — run `git diff` and `git status` to understand what changed.
2. **Stage all relevant files** — add modified and untracked files. Exclude files that should not be committed (`.env`, credentials, large binaries, generated files already in `.gitignore`).
   ```bash
   git add <file1> <file2> ...
   ```
3. **Write a commit message** — summarize the changes concisely. If `.claude/trello-active-card.json` exists, use the `cardName` to provide context (e.g. `fix: center newsletter popup heading`). Follow the project's commit style from recent `git log`.
4. **Commit:**
   ```bash
   git commit -m "<message>"
   ```

If the working tree is already clean, skip this step.

**Note:** Do not commit files that are listed in `.gitignore` or that look like secrets/credentials. If unsure about a file, ask the user.

#### Step 3: Remember the Branch Name

Save the current branch name (e.g. `fix-mobile-search-btn-center`) — you'll need it for the merge.

#### Step 4: Switch to Default Branch and Pull

```bash
git checkout <defaultBranch>
git pull
```

#### Step 5: Merge the Feature Branch

```bash
git merge {branch-name}
```

This should be a fast-forward merge. If it's not (i.e. there are conflicts), stop and report the conflict to the user — do not attempt to resolve it automatically.

#### Step 6: Push to Origin

```bash
git push
```

#### Step 7: Advance Trello Card

Check if `.claude/trello-active-card.json` exists. If it does:

1. Read the file to get `branchName`, `cardId`, `cardAuthorUsername`, `currentListId`, `currentListPos`, and `lists`.
2. **Branch guard:** Compare `branchName` from the state file against the branch being merged (saved in Step 3). If they don't match, **skip the entire Trello step** — the merge is unrelated to the active card. Do NOT delete the state file. Tell the user: `Skipped Trello — merged branch "{branch}" doesn't match active card branch "{branchName}".`
3. Sort `lists` by `pos` ascending. Find the list whose `pos` is the smallest value **greater than** `currentListPos`. This is the next list on the board.
4. If a next list exists, move the card there using the Trello MCP:
   ```
   move_card  cardId: <cardId>  listId: <next list id>  boardId: <board id>
   ```
5. **Add a summary comment** to the card explaining what was changed. The comment is for non-technical users:
   - **Start with `@<cardAuthorUsername>`** from the state file so the card author gets notified.
   - Write in a **casual, simple tone** — no technical jargon (no "CSS", "template", "commit", "merge", etc.)
   - **Language:** Match the language the card author used in the card description/comments. Default to **German** if unclear. Check the card's comments via `get_card_comments` to determine the language.
   - Summarize **what the user will see differently**, not what code changed.
   - Keep it to 1-3 short sentences.
   - Example (German): `@author Die Überschriften werden jetzt auf allen Seiten mittig angezeigt.`
   - Example (English): `@author The heading now shows up centered on all pages.`
   - Use `add_comment` with `cardId` and the summary text.

6. Delete the state file and the plan file:
   ```bash
   rm .claude/trello-active-card.json
   rm .plans/<branchName>.md 2>/dev/null
   ```

If the file does not exist, or the Trello MCP is not available, skip this step silently — it just means this task wasn't started via `/trello-next`.

If the card is already on the last list (no next list), delete the state file and plan file, and note it in the report.

#### Step 8: Report Success

Tell the user:
- Which branch was merged (`{branch-name}` → `<defaultBranch>`)
- The commit range shown in the merge output (e.g. `8b8525b..1be4cf1`)
- That the default branch has been pushed to origin
- If a Trello card was moved: which card and to which list

### Example Output

```
Merged fix-mobile-search-btn-center → master (8b8525b..1be4cf1)
Pushed master to origin
Trello: moved "Newsletter Popup: Spelling Error" → "Review"
```

### Error Handling

| Situation | Action |
|-----------|--------|
| Already on default branch | Ask user which branch to merge |
| Uncommitted changes | Stage and commit them before merging |
| Merge conflict | Stop, report conflict, do not auto-resolve |
| Push rejected | Stop, report rejection (e.g. non-fast-forward) |
| Not a fast-forward | Warn user and ask for confirmation before proceeding |

### Changing the Default Branch

Say "change default branch" at any time. The skill will update `.claude/git-config.json` with the new value.

### Notes

- This skill is the counterpart to `/git-new` — use that to start a branch, and this to finish it.
- After a successful merge, the feature branch is **not** deleted automatically. Ask the user if they want to clean it up:
  ```bash
  git branch -d {branch-name}
  git push origin --delete {branch-name}
  ```
