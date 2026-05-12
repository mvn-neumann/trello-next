---
name: log-time
description: Estimate total time spent on the current Trello card by analyzing git commits, then post a /spent comment to the card. Use when the user says "log time", "track time", "/log-time", "how long did this take", or "post time to Trello".
---

# Log Time

This skill estimates the total coding time spent on the current Trello card by analyzing git commit timestamps, then posts the result as a comment on the card in the format:

```
YYYY-MM-DD
/spent X.X hours
```

## Usage

```
/log-time
```

## Flow Overview

Steps 1 → 2 → 3 → 4 → 5

## Instructions

### Step 1: Load context

Read these **in parallel**:

1. **Active card state:**
   ```bash
   cat .claude/trello-active-card.json 2>/dev/null
   ```
   Extract: `cardId`, `cardName`, `cardUrl`, `branchName`, `startedAt` (ISO 8601, may be absent in older state files).

2. **Current branch and default branch:**
   ```bash
   git branch --show-current
   cat .claude/git-config.json 2>/dev/null
   ```

3. **Plan file** (using branch name from state or current branch):
   ```bash
   cat .plans/<branch-name>.md 2>/dev/null
   ```
   Note the `**Created:**` date if present.

4. **Existing time comments on the card** (to avoid double-counting):
   If the Trello MCP is available:
   ```
   get_card_comments  cardId: <cardId>
   ```
   Scan comments for any that contain `/spent` — extract the hours already logged.

**If no state file exists and the current branch is the default branch:** Tell the user there is no active card to log time for. Offer to let them specify a card URL or card ID manually.

**If no state file exists but the current branch is a `fix-*` or `feature-*` branch:** Proceed using the current branch name. Set `cardId` to null — the comment posting step (Step 5) will handle the missing card gracefully.

### Step 2: Get all commits on the branch

Run these **in parallel**:

1. **Commits on branch** (reverse-chronological so newest is first, but we process oldest-first):
   ```bash
   git log <defaultBranch>..<branchName> --format="%aI %H %s" --reverse
   ```
   This gives one line per commit: `ISO-timestamp hash subject`. If the output is empty (no commits yet), note it.

2. **Uncommitted changes:**
   ```bash
   git status --short
   git diff HEAD --stat
   ```
   If there are staged or unstaged changes, they represent work-in-progress that should add time to the estimate.

3. **Total lines changed (for calibration):**
   ```bash
   git diff <defaultBranch>..<branchName> --stat
   ```
   The number of changed lines helps sanity-check the estimate — a 500-line diff probably took more than 15 minutes.

**If there are zero commits AND no uncommitted changes:** Tell the user: "No commits found on this branch — nothing to estimate yet." End the skill here.

### Step 3: Estimate time from commit timestamps

Use the following algorithm to convert commit timestamps into a time estimate.

#### 3a. Parse and sort commits

Extract the ISO 8601 timestamp from each commit line. Sort by timestamp ascending (oldest first).

#### 3b. Group commits into sessions

A **session** is a group of consecutive commits where the gap between any two adjacent commits is ≤ **2 hours**. Iterate through the sorted timestamps and start a new session whenever the gap exceeds 2 hours.

#### 3c. Calculate duration per session

For each session:

| Session type | Duration formula |
|---|---|
| Single commit | 45 min flat |
| Multiple commits | (last\_commit − first\_commit) + **45 min** (30 min pre-work + 15 min wind-down) |

Cap any single session at **6 hours** — overnight commits or long gaps should not inflate estimates.

**Incorporate `startedAt` (if available):** If `startedAt` is present in the state file and falls in the same calendar day as the first session's first commit, and `startedAt` is earlier than (first\_commit − 30 min), extend the first session back to `startedAt` instead of first\_commit − 30 min.

**Add uncommitted work buffer:** If Step 2 found staged or unstaged changes, add **30 min** to account for the current in-progress session.

#### 3d. Sum and round

Total = sum of all session durations in hours.
Round to the nearest **0.25 h** (i.e., 15-minute intervals).

Minimum total: **0.25 h** (even if commits suggest less).

#### 3e. Check for previously logged time

If Step 1 found existing `/spent` comments on this card, sum the hours already logged and subtract them from the total to avoid double-counting. Note this in the breakdown shown to the user.

#### 3f. Build the breakdown string

Prepare a human-readable breakdown:

```
Time estimate for "<card title>":

  Session 1  Apr 10  09:25–10:10  (45 min, 2 commits)
  Session 2  Apr 17  11:00–12:45  (105 min, 6 commits)
  Uncommitted work               (+30 min)
  ─────────────────────────────────────────────────────
  Total: 3.0 hours (rounded from 2h 45m)
```

If there were previously logged hours:
```
  Previously logged: 1.5 hours
  New this session:  1.5 hours
  ─────────────────────────────
  Logging now:       1.5 hours
```

### Step 4: Review and confirm with user (hard gate)

Step 5 (posting to Trello) must **never** be reached before this step completes with an explicit user confirmation. If you have not yet rendered the breakdown and received an answer from `AskUserQuestion`, do not call `add_comment`.

1. Print the breakdown from Step 3f to the user as plain text. End it with the sentence:
   `Please review the estimate. Are the sessions, dates, and total hours correct?`

2. Then use `AskUserQuestion`:

**Question:** "Log X.X hours to the Trello card? Please review the breakdown above first."

**Options:**
- **"Yes, log X.X hours"** — the user has reviewed and the estimate is correct; proceed to Step 5.
- **"Adjust the hours"** — the estimate is wrong; ask the user for the corrected number as free text (e.g. "3.5"), then proceed directly to Step 5 with that value. **Do not** ask a second confirmation question after the user supplies the number.
- **"Cancel"** — end the skill without posting anything.

### Step 5: Post comment to Trello

Construct the comment text:
```
<YYYY-MM-DD>
/spent <X.X> hours
```

Where `<YYYY-MM-DD>` is today's date and `<X.X>` is the confirmed value formatted with one decimal place (e.g. `2.0`, `3.5`, `0.25` → `0.3`).

**Special rounding for display:** Always show one decimal place. If the value is a whole number, still show `.0` (e.g. `2.0 hours`, not `2 hours`).

**If `cardId` is known** (state file was present), post via Trello MCP:
```
add_comment  cardId: <cardId>  text: <comment text>
```

Confirm: `Logged X.X hours to "<card name>" on Trello.`

**If `cardId` is not known** (no state file), show the comment text to the user and ask them to paste it manually:
```
No active Trello card found. Here is the comment to paste manually:

2026-04-17
/spent 2.0 hours
```

---

## Output

| Result | What happens |
|--------|-------------|
| Success | Comment posted; user sees confirmation with card name and hours |
| No card ID | Comment text shown for manual copy-paste |
| No commits | Skill exits early with a message |
| User cancels | No comment posted |

---

## Error Handling

| Situation | Action |
|-----------|--------|
| No state file, on default branch | Tell user no active card found; offer manual card ID input |
| No commits on branch | Exit early: "No commits found — nothing to estimate yet" |
| `add_comment` MCP call fails | Show comment text for manual copy-paste |
| Trello MCP unavailable | Show comment text for manual copy-paste |
| User enters non-numeric hours | Re-ask for a valid number (loop within Step 4's Adjust branch) |
