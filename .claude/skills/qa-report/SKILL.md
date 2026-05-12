---
name: qa-report
description: Verify implemented changes by navigating the dev site, taking screenshots, and writing a QA report. Use after code changes are done, before /git-done. Use when the user says "verify changes", "qa report", "/qa-report", "check changes", or "take screenshots".
---

# QA Report

This skill verifies implemented changes by:
1. Reading what was changed from the plan file and git diff
2. Navigating the dev site and taking screenshots of affected areas
3. Writing a report to `.reports/<branch-name>.md` with embedded screenshots

## Usage

```
/qa-report
```

## Flow Overview

Steps 1 → 2 → 3 → 4 → 5 → 6

## Instructions

### Step 1: Load context

Read these **in parallel**:

1. **Active card state:**
   ```bash
   cat .claude/trello-active-card.json 2>/dev/null
   ```
   Extract: `cardId`, `cardName`, `cardUrl`, `branchName`.

2. **Current branch:**
   ```bash
   git branch --show-current
   ```

3. **Git config for default branch:**
   ```bash
   cat .claude/git-config.json 2>/dev/null
   ```

4. **Git user name:**
   ```bash
   git config user.name
   ```

After getting the branch name (from state file or current branch), read:

5. **Plan file:**
   ```bash
   cat .plans/<branch-name>.md 2>/dev/null
   ```
   Extract: plan steps, "Affected files" section, card title/URL (fallback if state file was missing).

6. **Git diff summary:**
   ```bash
   git diff <defaultBranch>..<branch-name> --stat
   git log <defaultBranch>..<branch-name> --oneline
   ```
   If the branch hasn't diverged from default yet, use `git diff HEAD --stat` and `git log --oneline -10`.

**If no plan file and no state file exist:** Ask the user what they implemented and what URLs to verify — continue from Step 2.

**If on the default branch:** Warn the user that `/qa-report` is meant to run on a feature/fix branch. Use `AskUserQuestion` to ask: "You're on `<branch>`. Continue anyway, or switch to a feature branch first?" Options: "Continue anyway" / "I'll switch branches first".

### Step 2: Resolve dev URL

Check `.claude/dev-config.json` for a `devUrl` field:
```bash
cat .claude/dev-config.json 2>/dev/null
```

If found and non-empty, use it silently.

If not found, ask the user with `AskUserQuestion`:
```
What is the local dev URL for this project?
```
Options: provide common options the user might be using based on project type (ddev, localhost:3000, localhost:8080, etc.), plus an "Other (type it)" option.

Save the entered URL to `.claude/dev-config.json`:
```json
{
  "devUrl": "https://example.ddev.site"
}
```
Confirm: `Saved dev URL to .claude/dev-config.json`

The URL is saved per-project so it is not re-asked on future runs.

### Step 3: Identify verification targets

From all available context, build a numbered list of verification targets — things to visually confirm in the browser:

**Sources to check (in priority order):**
1. Plan file **Steps** section — for each step, infer what a visual check looks like
2. Card **Goal** section (may have been added by `/trello-next` enrichment)
3. `git diff --stat` output — infer affected pages from file paths:
   - `templates/HomePage.ss` or `src/pages/index.*` → home page
   - `templates/ProductPage.ss` → a product detail page
   - `css/`, `scss/`, `styles/` → any page using those styles
   - `javascript/`, `js/`, `src/components/` → pages that use those components
4. Card title (if nothing else is available)

For each target, record:
- **n** — sequential number
- **check** — what to verify, written as a short assertion (e.g. "Heading is centred on desktop", "Popup closes when X is clicked")
- **url** — full URL including the `devUrl` base (e.g. `https://example.ddev.site/products/shirt`)
- **slug** — a short kebab-case label for the screenshot filename (e.g. `homepage-heading`, `popup-close`)

Show the list to the user before proceeding. If the list is empty, use `AskUserQuestion` to ask what to verify.

### Step 4: Take screenshots

Create the screenshots directory:
```bash
mkdir -p .reports/screenshots
```

**Detect the available browser tool** by trying each in order. Use the first that succeeds:

#### Option A: Playwright MCP

For each verification target (run in parallel where the tool supports it):

1. Navigate:
   ```
   mcp__playwright__browser_navigate  url: <target url>
   ```
2. Wait briefly for the page to settle, then screenshot:
   ```
   mcp__playwright__browser_screenshot  savePath: .reports/screenshots/<branch-name>-<n>-<slug>.png
   ```
   If `savePath` is not a supported parameter, retrieve the base64 result and decode it to file:
   ```bash
   echo "<base64_data>" | base64 -d > .reports/screenshots/<branch-name>-<n>-<slug>.png
   ```

#### Option B: Puppeteer MCP

For each verification target:

1. Navigate:
   ```
   mcp__puppeteer__puppeteer_navigate  url: <target url>
   ```
2. Screenshot:
   ```
   mcp__puppeteer__puppeteer_screenshot  name: <branch-name>-<n>-<slug>  width: 1280  height: 900
   ```
   Note the returned path and copy the file to `.reports/screenshots/<branch-name>-<n>-<slug>.png` if it was saved elsewhere.

#### Option C: Manual screenshots

If no browser MCP tool is available or both fail, ask the user to provide screenshots:

```
No browser tool is available. Please take a screenshot for each item below and paste it into the chat:

1. <check> — navigate to <url>
2. ...
```

For each pasted image, write it to `.reports/screenshots/<branch-name>-<n>-<slug>.png` using the `Write` tool.

---

After all screenshots are collected, **read each file** using the `Read` tool so the images are visible inline and can be analyzed for pass/fail.

### Step 5: Write the report

**File path:** `.reports/<branch-name>.md`

```bash
mkdir -p .reports
```

Write this content to the report file:

```markdown
# QA Report: <card title>

**Branch:** <branch-name>
**Card:** [<card title>](<card URL>)
**Date:** <YYYY-MM-DD>
**Author:** <git user.name>

## Summary of Changes

<git log output — one line per commit, newest first>

### Changed files

<git diff --stat output>

## Verification Results

<repeat for each target:>

### <n>. <Check description>

**URL:** <full target URL>
**Result:** ✅ Pass / ❌ Fail / ⚠️ Needs review

<One sentence observation: what the screenshot shows, or what is wrong if Fail>

![<check description>](./screenshots/<branch-name>-<n>-<slug>.png)

---

## Implementation Checklist

<Copy the Steps section from the plan file verbatim, preserving - [x] / - [ ] state.
If no plan file exists, write "No plan file found.">

## Notes

<Any observations, regressions, edge cases, or follow-up items noticed during QA.
Leave blank if none.>
```

**Determining Pass / Fail** — examine each screenshot after reading it:
- ✅ **Pass** — the intended change is visible and looks correct
- ❌ **Fail** — the change is missing, broken, or visually wrong; describe the specific problem
- ⚠️ **Needs review** — change appears to be there but cannot be fully confirmed from a static screenshot (e.g. requires interaction)

After writing the file, output a summary to the user:

```
Report written to .reports/<branch-name>.md

Results:
✅ 2 passed
❌ 1 failed — <brief description of failure>
⚠️ 1 needs review — <brief description>
```

If any items **failed**, describe them clearly so the developer can act immediately.

### Step 6: Offer to attach screenshots to Trello

If `.claude/trello-active-card.json` exists and the Trello MCP is available, ask the user with `AskUserQuestion`:

**Question:** "Attach screenshots to the Trello card?"

**Options:**
- **"Yes, attach all screenshots"** — upload each screenshot file to the Trello card:
  ```
  attach_image_to_card  cardId: <cardId>  imagePath: .reports/screenshots/<branch-name>-<n>-<slug>.png  name: "QA: <check description>"
  ```
  After all uploads: `Attached <n> screenshots to the Trello card.`
- **"No"** — skip; the report file is the deliverable.

If the state file does not exist, skip this step silently.

---

## Output files

| Path | Contents |
|------|----------|
| `.reports/<branch-name>.md` | Full QA report with pass/fail results and screenshot references |
| `.reports/screenshots/<branch-name>-<n>-<slug>.png` | One screenshot per verification target |

---

## Error Handling

| Situation | Action |
|-----------|--------|
| No plan file or state file | Ask user what was implemented and what URLs to check |
| Dev URL unreachable (connection refused / timeout) | Warn user; ask for the correct URL or to start the dev server first |
| Browser MCP unavailable | Fall back to manual screenshot workflow (Step 4 Option C) |
| Screenshot save fails | Note it in the report as "screenshot unavailable" and continue |
| No changes on branch | Warn user; still offer to verify any URL manually |
| Trello `attach_image_to_card` fails | Warn but don't abort — report file is still complete |
