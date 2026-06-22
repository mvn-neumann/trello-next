---
name: qa-screencast
description: Records an animated GIF of a browser interaction using CDP screencast frames. Use when the user says "screencast", "record", "animate", "gif", "capture animation", or "/qa-screencast".
---

# QA Screencast

Records a browser interaction as an animated GIF using Chrome's CDP `Page.startScreencast` API. Each browser paint is captured as a JPEG frame; ffmpeg combines them into a GIF.

## Usage

```
/qa-screencast
```

## Prerequisites

- `ffmpeg` must be installed on the host (`which ffmpeg`). If missing, suggest `sudo apt install ffmpeg` or `brew install ffmpeg`.
- The `mcp__playwright__browser_run_code_unsafe` tool must be available (it is loaded by default when the `playwright` MCP server is active).
- The dev server must be reachable (check `.claude/dev-config.json` for the base URL).

## Flow Overview

Steps 1 → 2 → 3 → 4 → 5 → 6

---

## Instructions

### Step 1: Load context

Read in parallel:

1. `cat .claude/trello-active-card.json 2>/dev/null` — extract `cardId`, `cardName`, `branchName`.
2. `git branch --show-current` — current branch name (fallback if state file missing).
3. `cat .claude/dev-config.json 2>/dev/null` — extract `devUrl`.
4. `which ffmpeg` — confirm ffmpeg is present; abort with a clear message if not.

If `devUrl` is not set, ask the user with `AskUserQuestion` and save to `.claude/dev-config.json`.

### Step 2: Clarify what to record

If the user's invocation message did not specify all of the following, ask with `AskUserQuestion`:

- **URL** — the page to navigate to (full URL including `devUrl`).
- **Action** — what to click or trigger (CSS selector or human description, e.g. `a[data-page-id="6"]`).
- **Duration** — how long to record after the action in milliseconds (default: 1500 ms).
- **Output filename** — short slug for the GIF (default: derived from branch name + `-screencast`).
- **slowAnimation** (optional) — playback rate for CSS animations/transitions as a decimal between 0 and 1. `0.2` = 20% speed (5× slower), `0.1` = 10× slower. Omit or set to `1` for normal speed. Parsed from args like `slow=0.2` or `slowAnimation=0.2` or simply `slow` (defaults to `0.2`). **When set, increase `Duration` proportionally** — e.g. if the animation normally finishes in 300 ms and you set `slow=0.2`, set duration to at least 1500 ms.

The user may provide these via the invocation args string (e.g. `/qa-screencast https://doitss4.ddev.site/ click=a[data-page-id="6"] 1500ms slow=0.2`). Parse what is available; ask only for what is missing.

### Step 3: Prepare the output directory

```bash
mkdir -p .reports/screencasts
```

### Step 4: Navigate to the target URL

```
mcp__playwright__browser_resize  width: 1280  height: 900
mcp__playwright__browser_navigate  url: <target URL>
```

Wait for the page to settle. Then hide the PHP debug bar so it doesn't appear in frames:

```
mcp__playwright__browser_evaluate  function: () => {
  const bar = document.querySelector('[id*="debugbar"], [class*="debugbar"]');
  if (bar) bar.style.display = 'none';
}
```

### Step 5: Record the screencast via CDP

Use `mcp__playwright__browser_run_code_unsafe` to run the following TypeScript code. This opens a CDP session, starts the screencast, triggers the action, waits, stops the screencast, and saves frames to disk.

**Exact code to execute (fill in `ACTION_SELECTOR`, `DURATION_MS`, and `PLAYBACK_RATE` from Step 2):**

```typescript
// CDP screencast — captures every browser paint as a JPEG frame
const fs = require('fs');
const path = require('path');

const outDir = '.reports/screencasts/frames';
fs.mkdirSync(outDir, { recursive: true });

const client = await page.context().newCDPSession(page);
let frameIndex = 0;

// Slow down CSS animations/transitions if requested
const PLAYBACK_RATE = <PLAYBACK_RATE>; // 1 = normal; 0.2 = 5× slower; 0.1 = 10× slower
if (PLAYBACK_RATE < 1) {
  await client.send('Animation.enable');
  await client.send('Animation.setPlaybackRate', { playbackRate: PLAYBACK_RATE });
}

client.on('Page.screencastFrame', async ({ data, sessionId }) => {
  const framePath = path.join(outDir, `frame_${String(frameIndex).padStart(4, '0')}.jpg`);
  fs.writeFileSync(framePath, Buffer.from(data, 'base64'));
  frameIndex++;
  // Acknowledge immediately so CDP keeps sending frames
  await client.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
});

await client.send('Page.startScreencast', {
  format: 'jpeg',
  quality: 85,
  maxWidth: 1280,
  maxHeight: 900,
  everyNthFrame: 1
});

// Trigger the action
const el = document.querySelector('<ACTION_SELECTOR>');
if (el) el.click();
else throw new Error('Element not found: <ACTION_SELECTOR>');

// Wait for animation to complete (increase this proportionally when slowAnimation is set)
await new Promise(r => setTimeout(r, <DURATION_MS>));

await client.send('Page.stopScreencast');

// Restore normal animation speed
if (PLAYBACK_RATE < 1) {
  await client.send('Animation.setPlaybackRate', { playbackRate: 1 });
}

// Brief pause to ensure the last frame event fires
await new Promise(r => setTimeout(r, 200));

return { frames: frameIndex, outDir };
```

**Notes:**
- Replace `<ACTION_SELECTOR>` with the actual CSS selector (e.g. `a[data-page-id="6"]`).
- Replace `<DURATION_MS>` with the duration integer (e.g. `1500`).
- Replace `<PLAYBACK_RATE>` with `1` when `slowAnimation` is not set, or the user-specified rate (e.g. `0.2`) when it is.
- The code calls `document.querySelector` — this is available because `browser_run_code_unsafe` runs in the Node.js Playwright context, where `page.evaluate` is not needed for direct DOM access via `el.click()`. If the selector triggers a Bootstrap event that expects a real click, use `await page.click('<ACTION_SELECTOR>')` instead of `el.click()`.
- If `require('fs')` throws (sandboxed environment), fall back to returning `{ frames: frameIndex, data: [] }` and use the manual decode path in Step 5b.

**Alternative action types** (replace the `el.click()` block as needed):

| Action | Code |
|--------|------|
| Click an element | `const el = document.querySelector('<SEL>'); if (el) el.click();` |
| Playwright click (real mouse event) | `await page.click('<SEL>');` |
| Keyboard press | `await page.keyboard.press('Tab');` |
| Hover | `await page.hover('<SEL>');` |
| Scroll | `await page.evaluate(() => window.scrollBy(0, 400));` |
| No action (record page load) | _(remove action block; extend duration)_ |

#### Step 5b: Fallback if `require('fs')` is unavailable

If the tool throws on `require('fs')`, re-run with this alternative that returns frames as base64 strings:

```typescript
const client = await page.context().newCDPSession(page);
const frames = [];

const PLAYBACK_RATE = <PLAYBACK_RATE>; // 1 = normal; 0.2 = 5× slower
if (PLAYBACK_RATE < 1) {
  await client.send('Animation.enable');
  await client.send('Animation.setPlaybackRate', { playbackRate: PLAYBACK_RATE });
}

client.on('Page.screencastFrame', async ({ data, sessionId }) => {
  frames.push(data);
  await client.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
});

await client.send('Page.startScreencast', { format: 'jpeg', quality: 85, maxWidth: 1280, maxHeight: 900, everyNthFrame: 1 });
await page.click('<ACTION_SELECTOR>');
await page.waitForTimeout(<DURATION_MS>);
await client.send('Page.stopScreencast');
if (PLAYBACK_RATE < 1) {
  await client.send('Animation.setPlaybackRate', { playbackRate: 1 });
}
await page.waitForTimeout(200);
return frames;
```

Then decode each frame to a file:
```bash
mkdir -p .reports/screencasts/frames
# For each frame index i and its base64 value $B64:
echo "$B64" | base64 -d > .reports/screencasts/frames/frame_$(printf '%04d' $i).jpg
```

### Step 6: Create the GIF with ffmpeg

After all frames are saved, verify frame count:

```bash
ls .reports/screencasts/frames/frame_*.jpg | wc -l
```

If 0 frames: report that CDP failed to deliver frames (likely the page had no paint events after the action). Suggest increasing `everyNthFrame: 1` → check browser version, or try the Playwright-native `page.screenshot()` loop approach.

If frames exist, create the GIF:

```bash
SLUG="<output-filename>"

ffmpeg -y \
  -framerate 15 \
  -pattern_type glob -i '.reports/screencasts/frames/frame_*.jpg' \
  -vf "fps=15,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
  -loop 0 \
  ".reports/screencasts/${SLUG}.gif" 2>&1 | tail -5
```

**Flags explained:**
- `-framerate 15` — input frame rate (match to actual frame delivery rate; CDP typically delivers 15–30 fps)
- `scale=640:-1` — scale to 640 px wide (preserves ratio); increase to 1280 for full-res (larger file)
- `palettegen` + `paletteuse` — two-pass GIF palette, produces much better colour quality than single-pass
- `-loop 0` — loop forever

**Adjust playback speed:** if the animation looks too fast or slow, change `-framerate`. Higher value = plays slower in the GIF; lower = faster. Default 15 is a good starting point.

**Cleanup frames** (optional, ask the user):

```bash
rm -rf .reports/screencasts/frames/
```

### Step 7: Display and report

Read the first and last saved frame with the `Read` tool so the user can see a preview:

```
Read  .reports/screencasts/frames/frame_0000.jpg   (first frame)
Read  .reports/screencasts/frames/frame_<last>.jpg  (last frame)
```

Report to the user:

```
Screencast saved: .reports/screencasts/<slug>.gif
Frames captured: <N>
Duration recorded: ~<N/15>s at 15fps
```

If the user wants to attach it to the Trello card, check `.claude/trello-active-card.json` for `cardId` and upload via:

```bash
bash .claude/scripts/trello-attach.sh <cardId> \
  ".reports/screencasts/<slug>.gif" \
  "Screencast: <description>"
```

---

## Error Handling

| Situation | Action |
|-----------|--------|
| ffmpeg not found | Abort; suggest `sudo apt install ffmpeg` |
| 0 frames captured | CDP not firing — try `everyNthFrame: 2`, check browser headless mode |
| `require('fs')` throws | Use fallback base64 path (Step 5b) |
| Action selector not found | Report clearly; ask user to verify the selector in DevTools |
| GIF file size > 10 MB | Re-run ffmpeg with `scale=480:-1` or `-framerate 10` to reduce size |
| Dev server unreachable | Prompt user to run `ddev start` |
| `Animation.setPlaybackRate` throws | CDP Animation domain not supported in this browser — omit the slow-animation block and re-run without `slowAnimation` |

## Output

| Path | Contents |
|------|----------|
| `.reports/screencasts/<slug>.gif` | Animated GIF of the recorded interaction |
| `.reports/screencasts/frames/` | Raw JPEG frames (delete after GIF is created) |
