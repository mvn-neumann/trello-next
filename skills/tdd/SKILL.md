---
name: tdd
description: Write tests first from the .specs/<branch>.md, implement the plan to make them pass, then hand off to /qa-report for visual scenarios. Use when the user says "tdd", "/tdd", "test first", "write failing tests", or "implement with tests".
---

# TDD

This skill drives implementation test-first using the scenarios written by `/spec`. Testable scenarios (`logic`, `interactive`) get a test written before the implementation code. Visual scenarios are left for `/qa-report`. At the end the full test suite must be green.

## Usage

```
/tdd
```

Run **after** `/git-new` (tracked test files must live on a `fix-*`/`feature-*` branch).

## Flow Overview

Steps 0 → 1 → 2 → (shortcut if all-visual) → 3 → 4 → 5 → 6 → 7 → 8

## Instructions

### Step 0: Branch guard

Check the current branch:

```bash
git branch --show-current
```

If not on a `fix-*` or `feature-*` branch, tell the user:

```
You must be on a fix-* or feature-* branch before writing test files.
Run /git-new first, then re-run /tdd.
```

Do **not** proceed until the user is on a valid branch.

### Step 1: Load context

Read these **in parallel**:

1. **Spec file:**
   ```bash
   cat .specs/<current-branch>.md 2>/dev/null
   ```
   If the spec file uses a different name (e.g. from an active-card state file), use that name instead.

2. **Active card state:**
   ```bash
   cat .claude/trello-active-card.json 2>/dev/null
   ```
   Extract: `branchName`, `cardName`, `cardUrl`.

3. **Plan file:**
   ```bash
   cat .plans/<branch-name>.md 2>/dev/null
   ```
   Extract: implementation steps, affected files.

4. **Test runner config:**
   ```bash
   cat .claude/test-config.json 2>/dev/null
   ```

**If no spec file exists:**

Ask the user with `AskUserQuestion`:

- **"Run /spec first"** — end this skill; the user should run `/spec` then re-run `/tdd`.
- **"Continue without spec"** — proceed to Step 3 (resolve test runner), skip Steps 4–5, and go straight to Step 6 (implement from the plan file only).

### Step 2: Filter and classify scenarios

Separate the spec's scenarios by type:

- **Testable:** `type: logic` → PHPUnit; `type: interactive` → Playwright E2E
- **Visual:** `type: visual` → no automated test; `/qa-report` handles these

**If all scenarios are `type: visual` (zero testable):**

Print:

```
Card is visual-only — no automated tests apply.
Implementing directly; verify with /qa-report after.
```

Skip to **Step 6** (implement the plan). After implementation, proceed to **Step 8** (hand off).

### Step 3: Resolve test runner

Check `.claude/test-config.json` for existing configuration. If the file exists and both commands are set, use them silently.

If the file does not exist or is missing a command, auto-detect and then **ask the user to confirm once**:

**PHPUnit detection:**
```bash
ls vendor/bin/phpunit 2>/dev/null || ls phpunit.xml* 2>/dev/null || ls phpunit.xml.dist 2>/dev/null
```
If found, default command: `ddev php vendor/bin/phpunit tests/`

**Playwright detection:**
```bash
ls tests/playwright/playwright.config.ts 2>/dev/null || ls tests/playwright/playwright.config.js 2>/dev/null
```
If found, default command to run from repo root: `cd tests/playwright && npx playwright test --reporter=line`

If ddev is not in use (check: `ls .ddev/config.yaml 2>/dev/null`), drop the `ddev` prefix from the PHPUnit command.

**If neither is detected:** Ask the user with `AskUserQuestion` for each applicable test command, or "None — skip test runner".

After confirming, save to `.claude/test-config.json`:

```json
{
  "phpunit": "ddev php vendor/bin/phpunit tests/",
  "playwright": "cd tests/playwright && npx playwright test --reporter=line"
}
```

Confirm: `Saved test runner config to .claude/test-config.json`

**Note:** Both keys are optional — if a project only has PHPUnit, omit the `playwright` key; if only Playwright, omit `phpunit`.

### Step 4: Write tests first

For each testable scenario, write the test file **before writing any implementation code**. Read one representative existing test to match conventions before generating.

#### PHPUnit (`type: logic`) — for each such scenario:

1. **Read a sample test** to match conventions:
   ```bash
   ls tests/*Test.php | head -1
   ```
   Then `Read` that file to see: extends class, fixture usage, naming conventions.

2. Write `tests/<ClassName>Test.php` (the name from the spec's "Test target" line, or derive from the scenario subject):
   - Extend `SapphireTest` (import: `use SilverStripe\Dev\SapphireTest;`)
   - One `test<CamelCase>` method per scenario
   - Method body: set up precondition → call the subject → `$this->assert*()`
   - Leave the assertion values as the expected outcomes from the scenario's "Then" line
   - If the class under test doesn't exist yet, the test will fail with a fatal — that is expected at this stage (soft red)

3. If the scenario needs fixture data, create `tests/<ClassName>Test.xml` following the project's existing fixture format.

#### Playwright E2E (`type: interactive`) — for each such scenario:

1. **Read `tests/playwright/tests/test-helpers.ts`** to understand the `preparePageForTest` helper.

2. Read one existing spec to match structure:
   ```bash
   ls tests/playwright/tests/*.spec.ts | head -1
   ```

3. Write `tests/playwright/tests/<slug>.spec.ts`:
   - `import { test, expect } from '@playwright/test';`
   - `import { preparePageForTest } from './test-helpers';`
   - One `test(...)` block per scenario
   - `await preparePageForTest(page)` at the start of each test
   - Steps follow the scenario's Given/When/Then: setup → action → assertion
   - The dev URL comes from `.claude/dev-config.json` (`devUrl` field) if it exists; otherwise leave a TODO comment and ask the user for the URL

**Write all test files before proceeding to Step 5.**

### Step 5: Baseline run (soft red)

Run the newly created tests (and only those — use file-specific flags where the runner supports them):

**PHPUnit (specific file):**
```bash
<phpunit-command> --filter <TestClassName>
```

**Playwright (specific file):**
```bash
cd tests/playwright && npx playwright test tests/<slug>.spec.ts --reporter=line
```

Show the user the output. Expected outcomes at this stage:
- PHPUnit: `Error` (class not found) or `Fail` — both are correct; the implementation hasn't been written yet.
- Playwright: `Error` or `Failed` — also expected.

If a new test **unexpectedly passes** at this stage, note it to the user:

```
⚠️  Scenario <n> ("<title>") passed before implementation — it may already be covered
    or the test may not be asserting the right thing. Review it before continuing.
```

Do **not** abort. Continue to Step 6.

### Step 6: Implement the plan

Follow each step in the plan file's **## Implementation Plan → Steps** section, checking them off in order (`- [ ]` → `- [x]` in the plan file as you go).

Apply the project's CLAUDE.md conventions:
- Only change what each step explicitly requires — no drive-by refactoring.
- After editing any CSS or JS under `themes/`, run `ddev composer vendor-expose` to publish to `public/_resources/` (only if CSS/JS files were modified).
- Do not add comments or docstrings to code you did not write.

### Step 7: Green run

Re-run the full test suite (all tests, not just the new ones) using the configured commands:

**PHPUnit:**
```bash
<phpunit-command>
```

**Playwright (if applicable):**
```bash
cd tests/playwright && npx playwright test --reporter=line
```

Show the full output.

**If tests are green:** Print:

```
✅ All tests passing.
```

Proceed to Step 8.

**If tests fail:**

1. Read the failure output carefully.
2. Identify the root cause — do not retry the same broken code.
3. Fix the implementation (or the test if the expectation was wrong) and re-run.
4. Repeat until green or until a failure is clearly a pre-existing issue unrelated to this card.

If a failure is **pre-existing** (the test was failing before this branch's changes — verify with `git stash && <run> && git stash pop`), note it to the user and continue:

```
⚠️  Pre-existing failure in <TestName> — not caused by this branch. Continuing.
```

### Step 8: Hand off

Print a summary:

```
## TDD complete: <card title>

Tests written:
  <list each new test file>

Result: ✅ <n> passing  ❌ <n> failing  ⚠️ <n> pre-existing

Visual scenarios (<n>) still need /qa-report verification.

Next steps:
  /qa-report — screenshot the visual changes
  /git-done  — merge and push when ready
```

If there were no visual scenarios (all testable), omit the `/qa-report` line.

---

## Test runner config format

**File path:** `.claude/test-config.json`

```json
{
  "phpunit": "ddev php vendor/bin/phpunit tests/",
  "playwright": "cd tests/playwright && npx playwright test --reporter=line"
}
```

Both keys are optional. Omit a key if the project does not use that test type.

---

## Error Handling

| Situation | Action |
|-----------|--------|
| No spec file | Ask user: run `/spec` first or continue without spec |
| Not on a fix-*/feature-* branch | Stop; tell user to run `/git-new` first |
| ddev not running | Warn user; suggest `ddev start`, do not retry in a loop |
| PHPUnit fatal (class not found) | Expected at soft-red stage; note it and continue |
| Playwright `devUrl` unknown | Ask user for the URL; save to `.claude/dev-config.json` |
| Pre-existing test failure | Note it; do not treat as a regression from this card |
| CSS/JS changed but vendor-expose skipped | Run `ddev composer vendor-expose` before the green-run |
