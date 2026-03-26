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

### 2. MCP Server

Add the Trello MCP entry to your project's `.mcp.json`. The launcher script reads credentials from the project root automatically — no secrets in the config file.

**Option A: Symlink the shared script** (recommended — stays up to date)
```bash
mkdir -p .claude/scripts
ln -sf ~/.claude/scripts/trello-mcp.sh .claude/scripts/trello-mcp.sh
```

**Option B: Copy the script**
```bash
mkdir -p .claude/scripts
cp ~/.claude/scripts/trello-mcp.sh .claude/scripts/trello-mcp.sh
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
.plans/
```

## Trello Board Layout

The skill auto-detects lists by name (case-insensitive). Your board should have lists matching these patterns:

| Role | Matched names |
|------|--------------|
| **To-Do** | "Zu Erledigen", "Abzuarbeiten", "Offen" |
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
| `/git-new` | Before file changes | Creates a `fix-*` or `feature-*` branch from the main branch |
| `/git-done` | When work is complete | Merges the branch, pushes, and moves the Trello card to the next list |

## What Gets Installed

```
~/.claude/
├── skills/
│   ├── trello-next/
│   │   └── SKILL.md              # Main skill — card fetching, analysis, planning
│   ├── git-new/
│   │   └── SKILL.md              # Branch creation workflow
│   └── git-done/
│       └── SKILL.md              # Merge, push, and Trello card advancement
└── scripts/
    └── trello-mcp.sh             # MCP launcher (reads creds from .env or _ss_environment.php)
```

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
