# trello-next

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that fetches Trello cards, analyzes them, and produces implementation plans. Includes dependent skills for git branch workflow (`/git-new`, `/git-done`) and a shared MCP launcher script.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Node.js + npm
- A Trello board with API access — get your API key and token at https://trello.com/power-ups/admin (create a Power-Up, then generate a token)
- Your `git config user.name` should match your Trello display name or username (the skill uses this to identify you on the board)

## Installation

```bash
git clone <repo-url> ~/codebase/trello-next
cd ~/codebase/trello-next
./install.sh
```

This installs shared skills and the launcher script to `~/.claude/`.

**Note:** If your project already has its own `/git-new` or `/git-done` skills in `.claude/skills/`, the install will overwrite the shared (global) versions in `~/.claude/skills/`. Project-local skills in `<project>/.claude/skills/` take precedence over global ones and are not affected.

## Per-Project Setup

Each project needs two things: credentials and the MCP server entry.

### 1. Credentials

Add your Trello credentials to the project. The launcher script checks these sources in order:

1. **Environment variables** (already exported in shell/CI)
2. **`.env` file** in project root (recommended)
3. **`_ss_environment.php`** in project root (SilverStripe projects)

**`.env` example:**
```bash
TRELLO_API_KEY=your-api-key
TRELLO_TOKEN=your-token
TRELLO_BOARD_ID=your-board-id
```

**`_ss_environment.php` example:**
```php
define('TRELLO_API_KEY', 'your-api-key');
define('TRELLO_TOKEN', 'your-token');
define('TRELLO_BOARD_ID', 'your-board-id');
```

The board ID is the short code in your Trello board URL: `https://trello.com/b/<BOARD_ID>/board-name`.

`trello-env.sh` picks `.env` vs `_ss_environment.php` by file presence: if `.env` exists it's
treated as SilverStripe 4+/5, otherwise `_ss_environment.php` is treated as SilverStripe 3. Don't
keep both in the same project — only one is read.

### 2. MCP Server

Add the Trello MCP entry to your project's `.mcp.json`. The launcher script reads credentials from the project root automatically — no secrets in the config file.

Both `trello-mcp.sh` and `trello-env.sh` (the credential resolver it sources) need to be
present — `trello-env.sh` is not optional, `trello-mcp.sh` fails immediately without it.

**Option A: Symlink the shared scripts** (recommended — stays up to date)
```bash
mkdir -p .claude/scripts
ln -sf ~/.claude/scripts/trello-mcp.sh .claude/scripts/trello-mcp.sh
ln -sf ~/.claude/scripts/trello-env.sh .claude/scripts/trello-env.sh
```

**Option B: Copy the scripts**
```bash
mkdir -p .claude/scripts
cp ~/.claude/scripts/trello-mcp.sh .claude/scripts/trello-mcp.sh
cp ~/.claude/scripts/trello-env.sh .claude/scripts/trello-env.sh
```

Then add to `.mcp.json`:
```json
{
  "mcpServers": {
    "trello": {
      "command": "bash",
      "args": [".claude/scripts/trello-mcp.sh"]
    }
  }
}
```

### 3. Gitignore

Add these to your project's `.gitignore` — they are generated at runtime:

```gitignore
.claude/trello-active-card.json
.claude/trello-home/
.plans/
.specs/
.reports/
```

## Running Multiple Trello-Backed Projects on One Machine

`@delorenj/mcp-server-trello` persists its "active board" to a **single file on the whole
machine**: `$HOME/.trello-mcp/config.json`. It reads that file on every server start and lets it
**override** whatever `TRELLO_BOARD_ID` the launcher exported — and any call to
`set_active_board` (from any project, any session) **overwrites it**. If you only ever work on
one Trello board, this is invisible. If you work on several projects, each with its own board,
it means:

- Project A calls `set_active_board` (or the skill infers it should) → the global file now holds
  A's board.
- Project B's Trello MCP server restarts (new session, IDE reload, etc.) → it reads the global
  file, silently loads **A's board** instead of B's, ignoring B's own `TRELLO_BOARD_ID`.
- `/trello-next` in B now reads cards from A's board, and — because `move_card` and `get_lists`
  resolve the board *differently* internally — can end up moving a card from A onto B's board, or
  vice versa.

`trello-mcp.sh` fixes this by giving the server a **private `$HOME`** per project
(`.claude/trello-home/`), so its state file can no longer be shared, and by **pinning** the
project's resolved `TRELLO_BOARD_ID` into that private file on every launch — a stray
`set_active_board` call self-heals on the next restart instead of poisoning other projects.

`skills/trello-next/SKILL.md` and `skills/git-done/SKILL.md` additionally never trust the
server's active board blindly: they resolve the project's board id independently (from the
pinned config or via `trello-env.sh`), verify it against `get_active_board_info`, and **abort
rather than proceed** on a mismatch.

**Rule of thumb: never call `set_active_board` yourself, and never let a skill call it on your
behalf.** It only ever helps the project you're in right now, at the cost of poisoning every
sibling project's next server start. If a skill reports the active board doesn't match the
project's board, the fix is to restart that project's Trello MCP server (its launcher re-pins the
correct board), not to call `set_active_board`.

## Trello Board Layout

The skill auto-detects lists by name (case-insensitive). Your board should have lists matching these patterns:

| Role | Matched names |
|------|--------------|
| **To-Do** | "To Do", "To-Do", "Zu Erledigen", "Abzuarbeiten", "Offen" |
| **In-Progress** | "In Bearbeitung", "In Arbeit" (or the list after To-Do) |
| **Review** | "Zur Prüfung", "Zur Prüfung durch Do it", "Review", "Prüfung" (or the list after In-Progress) |

If no To-Do list matches, the skill will show all available lists and ask which one to use.

The "Tasks" list (if present) is treated as a separate backlog and is ignored by this workflow.

## Usage

Inside your project directory, run:

```
/trello-next
```

Claude will:

1. Fetch your Trello board lists and identify you as a board member
2. Check for cards already assigned to you (in-progress or to-do)
3. Pick the oldest unassigned card if none are assigned
4. Fetch full card details (description, checklists, attachments, comments)
5. Analyze the issue and produce an implementation plan
6. Save the plan to `.plans/<branch-name>.md` for resumability
7. Move the card to the in-progress list
8. Offer to create a branch and start implementing

### Resuming Work

If you run `/trello-next` again and a plan file already exists for the selected card, the skill detects it, checks which steps have been completed, and asks whether to continue or re-plan.

### Dependent Skills

| Skill | Trigger | Description |
|-------|---------|-------------|
| `/spec` | After `/trello-next`, before `/git-new` | Writes `.specs/<branch>.md` with Given/When/Then scenarios; classifies each as logic, interactive, or visual |
| `/git-new` | Before file changes | Creates a `fix-*` or `feature-*` branch from the main branch |
| `/tdd` | After `/git-new` | Writes tests first from the spec, implements the plan, and runs the suite green |
| `/qa-report` | After `/tdd` (or after direct implementation), before `/git-done` | Takes screenshots of affected pages and generates a markdown QA report |
| `/qa-screencast` | Optional — alongside or after `/qa-report` | Records an animated GIF of a browser interaction via CDP screencast → `.reports/screencasts/<slug>.gif` |
| `/git-done` | When work is complete | Merges the branch, pushes, and moves the Trello card to the next list |
| `/log-time` | Any time after starting a card | Analyzes git commits, estimates hours worked, and posts a `/spent` comment to the Trello card |

## What Gets Installed

```
~/.claude/
├── skills/
│   ├── trello-next/
│   │   └── SKILL.md              # Main skill — card fetching, analysis, planning
│   ├── spec/
│   │   └── SKILL.md              # Spec writer — Given/When/Then scenarios with type classification
│   ├── tdd/
│   │   └── SKILL.md              # Test-first implementation driver — write tests, implement, run green
│   ├── git-new/
│   │   └── SKILL.md              # Branch creation workflow
│   ├── git-done/
│   │   └── SKILL.md              # Merge, push, and Trello card advancement
│   ├── qa-report/
│   │   └── SKILL.md              # Screenshot-based QA verification and report
│   ├── qa-screencast/
│   │   └── SKILL.md              # Animated GIF recorder via CDP screencast frames
│   └── log-time/
│       └── SKILL.md              # Git-based time estimation posted to Trello
└── scripts/
    ├── trello-mcp.sh             # MCP launcher — pins the board into a private $HOME (see below)
    ├── trello-env.sh             # Shared credential resolver, sourced by trello-mcp.sh and skills
    └── trello-attach.sh          # Uploads files as Trello card attachments
```

## Spec-driven + test-driven flow

The full SDD/TDD chain runs after `/trello-next` writes the plan and Acceptance Criteria:

```
/trello-next   ← fetches card, writes .plans/<branch>.md, pushes AC to Trello
/spec          ← writes .specs/<branch>.md with Given/When/Then scenarios
/git-new       ← creates fix-*/feature-* branch (tracked files require a branch)
/tdd           ← writes tests first, implements plan, runs suite green
/qa-report     ← screenshots visual scenarios (those without automated tests)
/qa-screencast ← (optional) records animated GIF of interactions via CDP
/git-done      ← merges branch, pushes, advances Trello card
```

### Scenario classification

`/spec` classifies each scenario into one of three types so `/tdd` knows what to automate:

| Type | Automated test | Signal |
|------|---------------|--------|
| `logic` | PHPUnit (`SapphireTest`) | PHP logic, helpers, models, API/data mapping |
| `interactive` | Playwright E2E | Click/toggle/submit/navigate, JS behavior |
| `visual` | None — use `/qa-report` | CSS, templates, spacing, layout, responsive |

Cards that are entirely visual (the common case for CSS/template work) skip test authoring entirely — `/tdd` detects "all visual" and goes straight to implementation, handing off to `/qa-report`.

### Per-project test runner config

`/tdd` auto-detects and saves test commands to `.claude/test-config.json` on first run. Example:

```json
{
  "phpunit": "ddev php vendor/bin/phpunit tests/",
  "playwright": "cd tests/playwright && npx playwright test --reporter=line"
}
```

Either key can be omitted if the project does not use that test type. The file is project-local and not committed.

## Customization

- **Default branch** — The skills auto-detect the default branch (`master`, `staging`, `main`, etc.) on first run and save it to `.claude/git-config.json` in the project root. You no longer need to configure this in `CLAUDE.md`. To change it later, say "change default branch" during any skill run.
- **Trello board ID** in the project's `.env` or `_ss_environment.php`
- **Trello list names** are matched by common patterns (see table above); rename your Trello lists to match, or the skill will prompt you

### `.claude/git-config.json`

This file is created automatically when `/git-new`, `/git-done`, or `/trello-next` runs for the first time. It stores the project's default branch:

```json
{
  "defaultBranch": "master"
}
```

You can also create it manually. To change the default branch at any time, say "change default branch" during a skill run, or edit the file directly.

## License

MIT
