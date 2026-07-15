---
name: spec
description: Write a formal spec (.specs/<branch>.md) with Given/When/Then scenarios derived from the Trello card's Acceptance Criteria and plan. Each scenario is classified as logic (PHPUnit), interactive (Playwright), or visual (/qa-report only). Use when the user says "spec", "/spec", "write spec", "write scenarios", or "specify".
model: sonnet
---

# Spec

This skill turns the implementation plan and Trello Acceptance Criteria into a formal, testable spec. Each scenario is classified so `/tdd` knows which ones to automate and which to defer to `/qa-report`.

## Usage

```
/spec
```

Run **after** `/trello-next` (which writes the plan and AC to Trello) and **before** `/git-new` (the spec is a planning artifact, like `.plans/`, written before any tracked files change).

## Flow Overview

Steps 1 → 2 → 3 → 4 → 5

## Instructions

### Step 1: Load context

Read these **in parallel**:

1. **Active card state:**
   ```bash
   cat .claude/trello-active-card.json 2>/dev/null
   ```
   Extract: `cardId`, `cardName`, `cardUrl`, `branchName`.

2. **Plan file** (use `branchName` from state file):
   ```bash
   cat .plans/<branch-name>.md 2>/dev/null
   ```
   Extract: full card description (including any Acceptance Criteria written by `/trello-next` Step 4c), implementation steps, affected files list.

3. **Default branch config:**
   ```bash
   cat .claude/git-config.json 2>/dev/null
   ```

4. **Check for existing spec file:**
   ```bash
   ls .specs/<branch-name>.md 2>/dev/null
   ```

**If no state file and no plan file exist:** Ask the user with `AskUserQuestion` what the card is about and what the branch name should be. Use those answers as the source for Step 2.

**If a spec file already exists:** Read it and present a summary:

```
A spec already exists for this card: .specs/<branch-name>.md

<n> scenarios total — <n logic>, <n interactive>, <n visual>

Re-generate the spec, or continue to /git-new then /tdd?
```

Use `AskUserQuestion` with options:
- **"Re-generate spec"** — overwrite the existing file; continue with Steps 2–5.
- **"Continue with existing spec"** — skip to Step 5 (output summary).

### Step 2: Derive scenarios

Using all content from the plan file (card description, Acceptance Criteria, implementation steps, affected files), produce a numbered list of **Given/When/Then** scenarios.

**Rules:**
- Each Acceptance Criteria checkbox (`- [ ]`) should map to at least one scenario. Write the scenario number next to the AC item to create an explicit link.
- Each implementation step that creates user-visible behavior or business logic should also produce a scenario.
- Scenario titles should be short, in imperative form (e.g. "Filter returns empty array for unknown ISO3 code").
- Scenarios are **outcomes**, not implementation details — they describe what a user or QA engineer would verify.

**Format each scenario as:**

```
Scenario N — <short title>
  Given <precondition / initial state>
  When  <action taken>
  Then  <expected observable outcome>
  Maps to: AC #<n> (or "plan step <n>" if no AC)
```

### Step 3: Classify each scenario

Tag each scenario with one of three types, using the affected-files list and the scenario verbs as signals:

| Type | Tag | Signal |
|------|-----|--------|
| PHP logic | `logic` | Affected files contain `*.php` under `app/`, `src/`, `mysite/`, `code/`, or `tests/`; scenario verbs: returns, calculates, maps, parses, validates, filters |
| Interactive JS/browser | `interactive` | Affected files contain JS/TS under `themes/*/javascript`, `themes/*/src`, or existing Playwright specs; scenario verbs: clicks, opens, closes, toggles, submits, navigates, shows, hides |
| Pure visual | `visual` | Affected files are only CSS/SCSS, `.ss` templates, or image assets; scenario verbs: looks, appears, renders, is styled, has colour, has font, has spacing, is responsive |

A single scenario can only have one type. When uncertain between `interactive` and `visual`, prefer `interactive` only if a JS action is required to reach the state; layout that is visible on load is `visual`.

Add the type tag directly after the scenario title line:

```
## Scenario 1 — Filter returns empty array for unknown ISO3 code   `type: logic`
```

Also add a **Test target** line for testable scenarios:
- `logic` → proposed PHPUnit file: `tests/<ClassName>Test.php`
- `interactive` → proposed Playwright file: `tests/playwright/tests/<slug>.spec.ts`
- `visual` → `(verified by /qa-report screenshot)`

### Step 4: Preview and approve

Print the **full proposed spec** in a fenced code block so the user can review all scenarios and their types before anything is written.

Then use `AskUserQuestion` to ask what to do:

- **"Push to Trello + save spec"** — write `.specs/<branch-name>.md` (create the directory if needed: `mkdir -p .specs`), then append a short **Spec** summary block to the Trello card description via `update_card_details`:

  Append text (after the existing description, separated by `\n\n---\n\n`):
  ```markdown
  ## Spec scenarios

  | # | Scenario | Type |
  |---|----------|------|
  | 1 | <title> | logic |
  | 2 | <title> | visual |
  ```

  Confirm: `Spec saved to .specs/<branch-name>.md and appended to Trello card.`

- **"Regenerate"** — prompt the user for guidance via the auto-provided "Other" free-text input. Re-synthesize scenarios incorporating that feedback, then loop back to the preview. Cap at 3 regeneration cycles; on the fourth, fall through to "Save spec only" automatically.

- **"Save spec only (skip Trello)"** — write `.specs/<branch-name>.md` but do not update the Trello card.

**If `update_card_details` fails:** log a warning and continue — the spec file is the authoritative artifact.

### Step 5: Output summary and next step

After saving the spec, print:

```
Spec written to .specs/<branch-name>.md

Scenarios:
  <n> logic     → PHPUnit tests to be written by /tdd
  <n> interactive → Playwright E2E tests to be written by /tdd
  <n> visual    → verified by /qa-report screenshots

Next steps:
  /git-new   — create the fix-*/feature-* branch
  /tdd       — write tests from this spec, then implement
```

If there are **zero testable scenarios** (all `visual`), note it explicitly:

```
All <n> scenarios are visual — no automated tests will be written.

Next steps:
  /git-new   — create the branch
  implement  — apply the plan steps directly
  /qa-report — verify the visual changes
```

---

## Spec file format

**File path:** `.specs/<branch-name>.md`

```markdown
# Spec: <card title>

**Card:** [<title>](<url>)
**Branch:** <branch-name>
**Created:** <YYYY-MM-DD>

---

## Scenario 1 — <short title>   `type: logic`

- **Given** <precondition>
- **When** <action>
- **Then** <expected outcome>
- **Maps to:** AC #1
- **Test target:** `tests/<Name>Test.php` (proposed)

## Scenario 2 — <short title>   `type: interactive`

- **Given** <precondition>
- **When** <action>
- **Then** <expected outcome>
- **Maps to:** AC #2
- **Test target:** `tests/playwright/tests/<slug>.spec.ts` (proposed)

## Scenario 3 — <short title>   `type: visual`

- **Given** <precondition>
- **When** <action>
- **Then** <expected outcome>
- **Maps to:** AC #3
- **Test target:** (verified by /qa-report screenshot)
```

---

## Error Handling

| Situation | Action |
|-----------|--------|
| No state file, no plan file | Ask user for card details; derive scenarios from conversation |
| Trello `update_card_details` fails | Save spec file anyway; log warning |
| No Acceptance Criteria in plan | Derive scenarios from implementation steps and card title; note in spec header |
| Branch name unknown | Ask the user; use the answer as the filename slug |
