---
name: qa-report
description: Verify implemented changes by navigating the dev site (and the live site for comparison, if reachable), taking annotated screenshots, and writing a QA report. Use after code changes are done, before /git-done. Use when the user says "verify changes", "qa report", "/qa-report", "check changes", or "take screenshots".
---

# QA Report

This skill verifies implemented changes by:
1. Reading what was changed from the plan file and git diff
2. Navigating the dev site (and, when reachable, the live site for a before/after comparison)
3. Closing overlays (debug bar, cookie consent, dialogs) before every screenshot
4. Marking what changed with simple stroke-only annotations (rectangles, arrows, numbers)
5. Writing a report to `.reports/<branch-name>.md` with embedded before/after screenshots

## Usage

```
/qa-report
```

## Flow Overview

Steps 1 → 2 → 3 → 3.5 → 4 → 5 → 6

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

### Step 2: Resolve dev and live URLs

Check `.claude/dev-config.json` for `devUrl` and `liveUrl` fields:
```bash
cat .claude/dev-config.json 2>/dev/null
```

**Dev URL** — if found and non-empty, use it silently. If not found, ask the user with
`AskUserQuestion`:
```
What is the local dev URL for this project?
```
Options: provide common options the user might be using based on project type (ddev, localhost:3000, localhost:8080, etc.), plus an "Other (type it)" option.

**Live URL** — used for a before/after comparison. If the `liveUrl` key is entirely absent
from the file (first run), ask once with `AskUserQuestion`:
```
Is there a live/production site to compare against? (optional)
```
Options: "Enter the live URL" (type it) / **"No live site — skip comparison"**.

- If the user provides a URL, save it as `liveUrl`.
- If the user opts out, save `"liveUrl": ""` — this is a deliberate sentinel meaning
  "skipped", so the question is never asked again on future runs of this skill.
- If the key is already present (URL or `""`) from a prior run, don't ask again — just use it.

Save/merge into `.claude/dev-config.json`:
```json
{
  "devUrl": "https://example.ddev.site",
  "liveUrl": "https://example.com"
}
```
Confirm: `Saved dev URL to .claude/dev-config.json` (and live URL, if newly set).

Both URLs are saved per-project so they are not re-asked on future runs. A target's live
page URL is the `liveUrl` base plus the same path as its dev target.

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
- **annotations** — one or more `{ selector, label, note }` triples identifying the specific
  element(s) that changed (CSS selector, a short number/letter label, a one-line note of what
  changed there), inferred from the diff/plan step. Leave empty if no single element can be
  pinned down (e.g. a page-wide layout shift) — the screenshot is still taken, just unmarked.

Show the list to the user before proceeding. If the list is empty, use `AskUserQuestion` to ask what to verify.

### Step 3.5: Prepare the page before every screenshot

Before **every** screenshot (dev, live, and annotated), clear overlays that would otherwise
leak into the shot. Run this after navigation and a short settle wait:

```
mcp__playwright__browser_evaluate  function: () => {
  // 1. Dismiss cookie-consent banners by clicking a known accept button
  const acceptSelectors = [
    '#accept-cookies', '.cookie-accept', '[data-cookie-accept]', '.cc-allow',
    '#CybotCookiebotDialogBodyButtonAccept', '[id*="cookie"] button'
  ];
  for (const sel of acceptSelectors) {
    const btn = document.querySelector(sel);
    if (btn) { btn.click(); break; }
  }

  // 2. Hide the PHP debug bar
  document.querySelectorAll('[id*="debugbar"], [class*="debugbar"], .phpdebugbar')
    .forEach(el => el.style.display = 'none');

  // 3. Hide any leftover cookie banners that didn't respond to a click
  document.querySelectorAll(
    '#CybotCookiebotDialog, .cc-window, [id*="cookie-consent"], [class*="cookie-notice"], ' +
    '[class*="cookie"][class*="banner"]'
  ).forEach(el => el.style.display = 'none');

  // 4. Hide open modals/dialogs/overlays
  document.querySelectorAll(
    '[role="dialog"], .modal.show, .modal-backdrop, [class*="overlay"][class*="open"]'
  ).forEach(el => el.style.display = 'none');
}
```

Also press Escape and dismiss any native browser dialog, in case a JS `alert`/`confirm` is
open:
```
mcp__playwright__browser_press_key  key: Escape
mcp__playwright__browser_handle_dialog  action: dismiss   (if a dialog is reported open)
```

After the screenshot, glance at it: if an overlay is still visible, take a
`mcp__playwright__browser_snapshot` to find its exact selector, hide that specific element
with a follow-up `browser_evaluate`, and re-take the screenshot.

### Step 4: Take screenshots

Create the screenshots directory:
```bash
mkdir -p .reports/screenshots
```

**Detect the available browser tool** by trying each in order. Use the first that succeeds.
For each verification target, capture up to three images: `-dev` (clean dev shot), `-live`
(clean live shot, if `liveUrl` is set and reachable), and `-annotated` (dev shot with the
change markers drawn on).

#### Option A: Playwright MCP

For each verification target (run in parallel across targets where the tool supports it):

1. **Dev shot:**
   ```
   mcp__playwright__browser_resize  width: 1280  height: 900
   mcp__playwright__browser_navigate  url: <dev target url>
   ```
   Wait briefly for the page to settle, run **Step 3.5** (prepare the page), then:
   ```
   mcp__playwright__browser_take_screenshot  filename: .reports/screenshots/<branch-name>-<n>-<slug>-dev.png
   ```
   If a file-saving parameter isn't supported, retrieve the base64 result and decode it to file:
   ```bash
   echo "<base64_data>" | base64 -d > .reports/screenshots/<branch-name>-<n>-<slug>-dev.png
   ```

2. **Live shot** (only if `liveUrl` is set):
   ```
   mcp__playwright__browser_navigate  url: <liveUrl base><target's path>
   ```
   If navigation errors out (connection refused, timeout, DNS failure) or the response is an
   obvious 404, treat the live site as unavailable for this target: skip the live shot, note
   "live unavailable" for this target, and move on — do not fail the whole run.
   Otherwise wait for settle, run **Step 3.5**, then screenshot to
   `.reports/screenshots/<branch-name>-<n>-<slug>-live.png` the same way as the dev shot.

3. **Annotated shot:** navigate back to the dev target URL, wait for settle, run **Step 3.5**,
   then inject the annotation overlay for this target's `annotations` list:
   ```
   mcp__playwright__browser_evaluate  function: (annotations) => {
     const svgNS = 'http://www.w3.org/2000/svg';
     const old = document.getElementById('__qa_anno');
     if (old) old.remove();
     const svg = document.createElementNS(svgNS, 'svg');
     svg.id = '__qa_anno';
     Object.assign(svg.style, {
       position: 'fixed', inset: '0', width: '100%', height: '100%',
       zIndex: 2147483647, pointerEvents: 'none'
     });
     annotations.forEach(a => {
       const el = document.querySelector(a.selector);
       if (!el) return;
       const r = el.getBoundingClientRect();
       // Stroke-only rectangle around the changed element — no fill.
       const rect = document.createElementNS(svgNS, 'rect');
       rect.setAttribute('x', r.x - 4);
       rect.setAttribute('y', r.y - 4);
       rect.setAttribute('width', r.width + 8);
       rect.setAttribute('height', r.height + 8);
       rect.setAttribute('fill', 'none');
       rect.setAttribute('stroke', '#e11');
       rect.setAttribute('stroke-width', '3');
       svg.appendChild(rect);
       // Number/label, drawn as text (no filled badge behind it).
       const t = document.createElementNS(svgNS, 'text');
       t.setAttribute('x', r.x - 8);
       t.setAttribute('y', Math.max(r.y - 8, 16));
       t.setAttribute('fill', '#e11');
       t.setAttribute('font-size', '20');
       t.setAttribute('font-weight', '700');
       t.textContent = a.label;
       svg.appendChild(t);
     });
     document.body.appendChild(svg);
   }  args: [<this target's annotations array>]
   ```
   Then screenshot to `.reports/screenshots/<branch-name>-<n>-<slug>-annotated.png`.
   If `annotations` is empty for this target, skip the overlay injection and just reuse the
   dev shot as the annotated one (copy the file rather than re-screenshotting).

   Use plain strokes only — rectangles, lines, arrows (two short angled strokes at the line's
   end), and number/letter labels. Do not draw filled shapes or semi-transparent overlays;
   they obscure the underlying UI the reviewer needs to see.

#### Option B: Puppeteer MCP

For each verification target, same three-shot pattern as Option A:

1. Navigate: `mcp__puppeteer__puppeteer_navigate  url: <target url>`
2. Screenshot: `mcp__puppeteer__puppeteer_screenshot  name: <branch-name>-<n>-<slug>-dev  width: 1280  height: 900`
   (repeat with `-live` and `-annotated` suffixes for the other two shots; Puppeteer has no
   built-in DOM-evaluate step in this fallback, so the annotated shot may simply reuse the dev
   shot with a note in the report that annotation wasn't available via this tool).
   Note the returned path and copy the file to `.reports/screenshots/<branch-name>-<n>-<slug>-{dev,live,annotated}.png` if it was saved elsewhere.

#### Option C: Manual screenshots

If no browser MCP tool is available or both fail, ask the user to provide screenshots:

```
No browser tool is available. Please take a screenshot for each item below and paste it into the chat:

1. <check> — navigate to <dev url> (and <live url>, if available)
2. ...
```

For each pasted image, write it to `.reports/screenshots/<branch-name>-<n>-<slug>-dev.png` (or
`-live.png`) using the `Write` tool. Manual annotation isn't possible in this fallback — note
in the report that the change markers are missing and describe the change in prose instead.

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

**URL:** <full dev target URL>
**Result:** ✅ Pass / ❌ Fail / ⚠️ Needs review

<One sentence observation: what the screenshot shows, or what is wrong if Fail>

**Before (live):**
![<check description> — live](./screenshots/<branch-name>-<n>-<slug>-live.png)
<or, if liveUrl was skipped/unreachable for this target:>
_Live site not available — dev-only capture._

**After (dev, annotated):**
![<check description> — dev annotated](./screenshots/<branch-name>-<n>-<slug>-annotated.png)

**Changes marked:**
<numbered list matching each annotation label to its note, e.g.:>
1. Hero heading now centred on mobile
2. New "Book now" button added below the fold
<omit this list if the target had no annotations>

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

If `.claude/trello-active-card.json` exists and Trello API credentials are resolvable, ask the user with `AskUserQuestion`:

**Question:** "Attach screenshots to the Trello card?"

**Options:**
- **"Yes, attach all screenshots"** — upload each screenshot file to the Trello card.

  Attach the `-annotated` screenshot for each target (the most informative single image),
  plus the `-live` screenshot where one exists, so the card shows both the marked-up change
  and the live-site reference.

  **Choose the right method based on whether the dev URL is publicly reachable:**

  - **Public URL** (staging server, live site): use the MCP tool:
    ```
    attach_image_to_card  cardId: <cardId>  imagePath: .reports/screenshots/<branch-name>-<n>-<slug>-annotated.png  name: "QA: <check description>"
    ```

  - **Local dev screenshot** (ddev, localhost — Trello's servers cannot reach these URLs):
    use the curl script instead:
    ```bash
    bash .claude/scripts/trello-attach.sh <cardId> \
      .reports/screenshots/<branch-name>-<n>-<slug>-annotated.png \
      "QA: <check description>"
    ```
    The script resolves Trello credentials from env vars → `.env` → `_ss_environment.php`
    and uploads the file directly via the Trello REST API. It prints the attachment ID on
    success and exits 1 with an error message on failure.

  The `-live` screenshot (when present) is always publicly reachable by definition, so attach
  it via the MCP tool regardless of which method was used for the dev shot.

  After all uploads: `Attached <n> screenshots to the Trello card.`

- **"No"** — skip; the report file is the deliverable.

If the state file does not exist, skip this step silently.

---

## Output files

| Path | Contents |
|------|----------|
| `.reports/<branch-name>.md` | Full QA report with pass/fail results and before/after screenshot references |
| `.reports/screenshots/<branch-name>-<n>-<slug>-dev.png` | Clean dev-site screenshot, overlays closed |
| `.reports/screenshots/<branch-name>-<n>-<slug>-live.png` | Clean live-site screenshot, overlays closed (only when `liveUrl` is set and reachable for this target) |
| `.reports/screenshots/<branch-name>-<n>-<slug>-annotated.png` | Dev-site screenshot with stroke-only change markers (rectangles/lines/arrows/numbers) |

---

## Error Handling

| Situation | Action |
|-----------|--------|
| No plan file or state file | Ask user what was implemented and what URLs to check |
| Dev URL unreachable (connection refused / timeout) | Warn user; ask for the correct URL or to start the dev server first |
| Live URL unreachable (connection refused / timeout / 404) | Skip the live shot for that target, mark it "Live site not available" in the report, continue with dev-only |
| Overlay (debug bar / cookie consent / dialog) still visible after Step 3.5 | Take a `browser_snapshot` to find its selector, hide that specific element, re-take the screenshot |
| Browser MCP unavailable | Fall back to manual screenshot workflow (Step 4 Option C) |
| Screenshot save fails | Note it in the report as "screenshot unavailable" and continue |
| No changes on branch | Warn user; still offer to verify any URL manually |
| Trello attachment upload (curl) fails | Warn but don't abort — report file is still complete |
