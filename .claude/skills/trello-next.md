---
name: trello-next
description: Fetch the oldest card from the Trello "To-Do" list, analyze the issue, and produce an implementation plan. Use when the user says "next task", "what's next", "trello next", "/trello-next", or "get next issue".
---

# Trello Next

This skill fetches the oldest card from the Trello "To-Do" list, reads all its details, analyzes what needs to be done, and produces a concrete implementation plan.

## Usage

```
/trello-next
```

## Flow Overview

There are two paths through this skill depending on whether a plan file already exists for the selected card:

- **New card** — Steps 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → user chooses:
  - **"Start implementing"** → create branch and begin work
  - **"Discuss the plan"** → wait for user input
  - **"Just the plan"** → stop here
- **Resuming card with existing plan** — Steps 1 → 2 → 3 → 4 → 5 → 6 (check plan) → user chooses:
  - **"Continue"** → skip to Step 10 → 11
  - **"Re-plan"** → continue with Steps 7 → 8 → 9 → 10 → 11

## Instructions

### Step 1: Fetch board data, identify user, and resolve default branch (parallel)

First, **check the cache**. Read `.claude/trello-active-card.json` (it may exist from a previous run). If it exists AND contains both `lists` (non-empty array) and `boardMembers` (non-empty array) AND `cachedAt` is less than 1 hour ago:
- Use the cached `lists` and `boardMembers` directly - skip the `get_lists` and `get_board_members` MCP calls.
- Only run calls 2 and 4 below (git user name + git config).

Otherwise, make these four calls **in parallel** (they have no dependencies on each other):

1. **Get all lists:**
   ```
   get_lists
   ```

2. **Get git user name:**
   ```bash
   git config user.name
   ```

3. **Get board members:**
   ```
   get_board_members
   ```

4. **Read git config for default branch:**
   ```bash
   cat .claude/git-config.json 2>/dev/null
   ```
   If the file exists and contains a `defaultBranch` value, save it for later use in Step 11. If the file does not exist, the default branch will be resolved in Step 10c.

**Process the results:**

Save **all** lists with their `id`, `name`, and `pos` (position on the board), sorted by `pos` ascending. This ordered list is needed later to determine the "next" list for a card.

Find these lists by name (case-insensitive) and save their `id`s:
- **To-Do list** — matches any of: "Zu Erledigen", "Abzuarbeiten", "Offen"
- **In-Progress list** — matches any of: "In Bearbeitung", "In Arbeit". If no name matches, fall back to the list immediately after the To-Do list by `pos`.
- **Review list** — matches any of: "Zur Prüfung", "Zur Prüfung durch Do it", "Review", "Prüfung". If no name matches, fall back to the list immediately after the In-Progress list by `pos`. If no list exists after In-Progress, leave this as `null`.

**Note:** The "Tasks" list is a separate backlog/inbox and is NOT managed by this workflow. Do not fetch cards from it.

If no To-Do list is found, show the user ALL available list names and ask which one to use.

**Match the git user name** (case-insensitive) against each member's `fullName` and `username`. Try in order:
1. **Exact match** — git name equals `fullName`
2. **Contains match** — git name contains `fullName`, or `fullName` contains git name
3. **Username match** — git name (lowercased, spaces removed) contains `username`, or `username` contains any word from the git name

If exactly one member matches, save that member's `id` and `fullName` — no need to ask the user.

If no match is found, fall back to asking the user via `AskUserQuestion` with each board member as an option.

### Step 2: Check for cards already assigned to me

Fetch all cards assigned to the current user (this is a lightweight call that avoids fetching entire lists):

```
get_my_cards
```

**Response hygiene:** This call can return large payloads (full card objects across all boards). After receiving the response, extract only `id`, `name`, and `idList` from each card. Discard all other fields - do not retain descriptions, checklists, or attachments from this call.

Filter the results by `idList` to separate:
- **My in-progress cards** — cards where `idList` matches the in-progress list ID
- **My to-do cards** — cards where `idList` matches the To-Do list ID

**If there are cards assigned to me in the in-progress list**, present only those:

```
You have cards already in progress in "<list name>":
1. <card name 1>
2. <card name 2>

Pick up one of your cards, or grab a new one from "<To-Do list name>"?
```

Use `AskUserQuestion` with options for each of the user's in-progress cards plus a "New card from To-Do" option.

- If the user picks an existing card, use that card and **skip Step 3** (go straight to Step 4).
- If the user picks "New card from To-Do", continue to Step 3.
- If there are no in-progress cards assigned to me, continue to Step 3 automatically.

**Note on Trello API eventual consistency:** After a `move_card` call, `get_my_cards` may still return the card under its old `idList` for a few seconds. If a card appears in the To-Do list but was recently moved to In-Progress (e.g. in a previous `/trello-next` run), treat it as an in-progress card. Compare against `trello-active-card.json` if it exists.

### Step 3: Pick a card from To-Do

**If the user has cards assigned to them in the To-Do list** (from the `get_my_cards` result in Step 2), pick the oldest one by `id` ascending. Save its `id` and `name`. Skip to Step 4.

**Otherwise**, fetch all cards from the To-Do list to find unassigned cards:

```
get_cards_by_list_id  listId: <to-do list id>
```

**Response hygiene:** This call returns full card objects for every card in the list. After receiving the response, extract only `id`, `name`, and `idMembers` from each card. Discard all other fields immediately - do not retain full descriptions, checklists, or attachments from this list call.

Filter for **unassigned cards only** — cards with empty `idMembers`. Sort by `id` ascending (oldest first). Pick the oldest one. Save its `id` and `name`.

Assign the current user to the card so other developers know it's taken:

```
assign_member_to_card  cardId: <card id>  memberId: <current user id>
```

If no unassigned cards exist, tell the user: "No cards available for you in the To-Do list — all remaining cards are assigned to other members." If the list is completely empty, tell the user: "The To-Do list is empty — nothing to work on."

### Step 4: Fetch full card details

Use `get_card` with `includeMarkdown: true` to get the complete card with checklists, attachments, labels, members, and comments in one call:

```
get_card  cardId: <card id from step 2 or 3>  includeMarkdown: true
```

Collect:
- **Title** (`name`)
- **Description** (`desc`) — may contain Markdown
- **Labels** (color + name)
- **Due date** (if set)
- **Checklists** — list all items and their completion state
- **Attachments** — note any linked images or files
- **Comments** — all comment texts
- **Card URL** (`url` or `shortUrl`) — the link to the card on Trello
- **Card author username** — from `idMemberCreator`, match against board members to get the Trello username. Save this for the state file in Step 10b.

### Step 5: Derive branch name

Derive the branch name now so it can be included in the plan file (Step 9).

- Determine the scope: use `fix-` for bugs, `feature-` for new features or content changes
- Take the card title, lowercase it, replace spaces and special characters with hyphens, remove consecutive hyphens, trim to ~40 chars max
- Append the first 8 characters of the Trello card ID as a suffix (for traceability)
- Example: card "Newsletter Popup: Spelling Error" (ID `507f1f77bcf86cd799439011`) → `fix-newsletter-popup-spelling-error-507f1f77`

Save the branch name — it will be used in the plan file and in the final output.

### Step 6: Check for existing plan file

Check if a plan file already exists for the selected card. The plan file uses the same slug as the branch name from Step 5:

```bash
ls .plans/<branch-name>.md 2>/dev/null
```

**If a plan file exists for this card:**

1. **Read the plan file** to see what was previously planned.
2. **Check implementation status** — compare the plan's steps against the current codebase:
   - Run `git log --oneline -10` to check for recent commits related to the card.
   - Glob/Grep for files mentioned in the plan's "Affected files" section to see if changes were made.
   - Check for uncommitted work (`git status`).
3. **Update the checkboxes** in the plan file — change `- [ ]` to `- [x]` for steps that have been completed.
4. **Present the card summary** (same format as Step 8) along with a status summary:

   ```
   ## Resuming: <card title>

   **Trello:** <card URL>
   **Plan file:** .plans/<branch-name>.md

   ### Implementation status
   - [x] 1. Step one — done (commit abc1234)
   - [ ] 2. Step two — not started
   - [ ] 3. Step three — not started

   Continue with this plan, or re-plan?
   ```

5. Use `AskUserQuestion` with options:
   - **"Continue with this plan"** — skip Steps 7-9, go directly to Step 10 (move card / save state)
   - **"Re-plan"** — continue with Step 7 (analyze), then Step 8 (present summary), Step 9 (write plan, overwriting the existing file)

**If no plan file exists for this card:** Continue to Step 7.

### Step 7: Analyze the issue

Read all collected data from Step 4 carefully. Identify:

- **What** needs to be done (the core task)
- **Why** it matters (context from description/comments)
- **Where** in the codebase it likely applies (based on labels, description keywords, and your knowledge of this project)
- **Scope** — is this a bug fix, a new feature, a refactor, or a content update?
- **Open questions** — anything ambiguous or missing from the card

### Step 8: Present the card summary

Show the user a concise summary:

```
## Next Task: <card title>

**Trello:** <card URL>
**Labels:** <labels or "none">
**Due:** <date or "none">

### Description
<card description — render as markdown>

### Checklist items
- [ ] item 1
- [x] item 2 (done)

### Comments
> <most recent comment>
```

### Step 9: Write implementation plan to file

Write the plan to a persistent file so it can be resumed in a fresh session without re-fetching from Trello.

**File path:** `.plans/<branch-name>.md`

The plan file uses the branch name from Step 5 as the filename (e.g., `fix-newsletter-popup-spelling-error-507f1f77.md`). This makes plan files human-readable when browsing the directory.

Create the `.plans/` directory if it doesn't exist. The file must be self-describing — it contains all context needed to resume work.

Write the following content to the plan file:

```markdown
# Plan: <card title>

**Card ID:** <card id>
**Trello:** <card URL>
**Labels:** <labels or "none">
**Due:** <date or "none">
**Branch:** <branch name from Step 5>
**Created:** <current date YYYY-MM-DD>

## Card Description

<full card description — render as markdown>

## Card Comments

<all comments, newest first, with author and date>

## Analysis

- **What:** <core task>
- **Why:** <context>
- **Scope:** <bug fix / feature / refactor / content update>

## Implementation Plan

### Affected files
- `path/to/file.ext` — reason

### Steps
- [ ] 1. **Step title** — short description of what to do and why
- [ ] 2. …

### Open questions / risks
- Question or uncertainty that needs clarification before starting
```

**Important:** Use `- [ ]` checkbox syntax for each step so that the plan-file check in Step 6 can later determine completion status by checking for `- [x]` vs `- [ ]`.

After writing the file, also **output the Implementation Plan section to the user** so they can see it immediately.

### Step 10: Move card and save state

#### Step 10a: Move card on Trello

**If the card came from the To-Do list (Step 3):** Move it to the in-progress list identified in Step 1:

```
move_card  cardId: <card id>  listId: <in-progress list id>  boardId: <board id>
```

**Important:** `boardId` must be passed explicitly — the default board is not applied automatically by `move_card`.

Tell the user: `Moved card to "<list name>".`

If the To-Do list is the last list on the board (no list after it), skip the move silently.

**If the card was already in the in-progress list (Step 2):** Do not move it — it's already where it should be.

#### Step 10b: Save state for `/git-done`

**Read** `.claude/trello-active-card.json` first (it may already exist from a previous run), then overwrite it with the new card data:

```json
{
  "boardId": "<board id>",
  "cardId": "<card id>",
  "cardName": "<card title>",
  "cardUrl": "<card URL>",
  "branchName": "<branch name from Step 5>",
  "cardAuthorUsername": "<Trello username of the card creator from Step 4>",
  "sourceListId": "<list the card was in before /trello-next picked it up>",
  "sourceListName": "<name of that list>",
  "currentListId": "<list the card is currently in after Step 10a move>",
  "currentListPos": <pos of that list>,
  "reviewListId": "<review list id or null>",
  "reviewListName": "<review list name or null>",
  "lists": [
    { "id": "...", "name": "...", "pos": 123 }
  ],
  "boardMembers": [
    { "id": "...", "fullName": "...", "username": "..." }
  ],
  "cachedAt": "<ISO 8601 timestamp, e.g. 2026-03-27T14:30:00Z>"
}
```

This file allows `/git-done` to move the card to the review list when work is complete. If `reviewListId` is `null`, `/git-done` falls back to the next list by position. The `boardMembers` and `cachedAt` fields allow Step 1 to skip `get_lists` and `get_board_members` MCP calls when the cache is fresh (< 1 hour old).

#### Step 10c: Resolve default branch (if not already known)

If `.claude/git-config.json` was not found in Step 1 (call 4), resolve the default branch now before `/git-new` is called:

1. Auto-detect:
   a. Run: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`
   b. If that fails, check: does `origin/main` exist? (`git rev-parse --verify origin/main 2>/dev/null`) Then try `origin/master`.
   c. If detected, ask the user to confirm: "Detected default branch: `<branch>`. Is this correct? (Yes / No, it's: ___)"
   d. If auto-detection fails entirely, ask with AskUserQuestion: "What is the default branch for this project?" (free text)
2. Write the result to `.claude/git-config.json`:
   ```json
   {
     "defaultBranch": "<branch>"
   }
   ```
3. Confirm: "Saved default branch `<branch>` to `.claude/git-config.json`."

This ensures `/git-new` (called in Step 11) will find the config file and skip its own auto-detection.

### Step 11: Prompt user for next action

Use `AskUserQuestion` to ask what the user wants to do next:

**Question:** "What would you like to do?"

**Options:**
- **"Start implementing"** — Run `/git-new <branch-name-from-step-5>` to create the branch, then immediately begin implementing the plan. No further user input needed.
- **"Discuss the plan"** — Run `/git-new <branch-name-from-step-5>` to create the branch (since a plan file was already written), then wait for the user's input to discuss, clarify, or adjust the plan.
- **"Just the plan"** — The user only wanted the analysis and plan. End the skill here — do not create a branch or start implementing.
- **"Skip this card"** — The user wants to reject this card and pick a different one:
  1. Move the card back to its original list if it was moved in Step 10a.
  2. Update the card's position to the **bottom** of the To-Do list so other cards get picked first: use `update_card_details` with `pos: "bottom"` (or set `pos` to a value higher than all other cards in the list).
  3. Unassign the current user from the card (if they were assigned in Step 3).
  4. Delete the plan file if one was just created in Step 9.
  5. **Go back to Step 3** to pick the next card. Reuse the already-fetched card list from Step 3 — do not re-fetch from Trello. Just exclude the skipped card and pick the next oldest. If no cards remain, tell the user there are no more cards available.

---

## Error Handling

| Situation | Action |
|-----------|--------|
| Trello MCP not configured | Tell user to add `mcp-server-trello` to `.mcp.json` with their API key/token and board ID |
| Trello MCP fails to start | See **Fixing a broken Trello MCP** below |
| No matching list found | List ALL available list names and ask the user which one to use |
| List is empty | Tell user the list is empty |
| Card has no description | Proceed with title only; note the missing description in open questions |
| MCP tool call fails | Show the error and suggest the user checks their Trello API credentials |

### Fixing a broken Trello MCP

If `/mcp` shows "Failed to reconnect to trello", the most likely cause is a **corrupted npx cache**. Fix it with these steps:

1. **Find the corrupted cache directory:**
   ```bash
   for dir in ~/.npm/_npx/*/; do
     if ls "$dir/node_modules/@delorenj" 2>/dev/null >/dev/null; then
       echo "Found: $dir"
     fi
   done
   ```

2. **Delete it:**
   ```bash
   rm -rf ~/.npm/_npx/<hash-from-step-1>
   ```

3. **Verify the server starts cleanly:**
   ```bash
   TRELLO_API_KEY="$TRELLO_API_KEY" TRELLO_TOKEN="$TRELLO_TOKEN" TRELLO_BOARD_ID="$TRELLO_BOARD_ID" \
     npx -y @delorenj/mcp-server-trello &
   sleep 5
   kill %1  # should show exit 143 (SIGTERM), meaning it was running
   ```

4. **Restart Claude Code** — the MCP should now connect.

If the cache is not the issue, run the server directly with `node` to see the real error:
```bash
node ~/.npm/_npx/<hash>/node_modules/@delorenj/mcp-server-trello/build/index.js
```
