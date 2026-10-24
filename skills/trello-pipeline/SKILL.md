---
name: trello-pipeline
description: Create Trello cards from numbered plan files (.plans/NN-*.md), then work through them one by one — each card implemented by /trello-next in its own subagent, then reviewed; passed cards move to Fertig, failed cards and implementer gates are first judged by a decide agent: a feasible recommended option is taken and fixed automatically (the decide agent always runs, product decisions included; the user can veto by comment until the merge); only when no feasible option exists the card blocks until the user comments an instruction. With `watch on` a cron watcher starts it headless from a card comment. Use when the user says "trello pipeline", "/trello-pipeline", "cards from plans", "run all plans", "work through the plans", or "trello pipeline watch".
---

# Trello Pipeline

Turns `.plans/00-*.md … NN-*.md` into Trello cards and drives them to "Fertig" — one subagent at a time, with a review gate after every card.

## Usage

```
/trello-pipeline                 # setup (if no state file yet), then start the loop
/trello-pipeline setup [NN-MM]   # create cards only (optional range, e.g. 00-02)
/trello-pipeline tick            # one loop step (what /loop calls)
/trello-pipeline status          # read-only overview
/trello-pipeline plan-push NN    # replace the card's plan attachment with the local .plans/NN-*.md
/trello-pipeline watch on|off|status  # start from a card comment via cron (see "Start from a comment (cron)")
```

Arguments are in `$ARGUMENTS`. No argument → `setup` if `.plans/.trello-pipeline.json` is missing, then Step "Start the loop" (with its heartbeat check). `setup` on a machine without `.plans/` restores plans and state from the board (see "Restore").

## Rules (always)

- **Exactly one subagent at a time.** Never in parallel — cards build on each other. A blocked card does not stop the others: independent cards go on while it waits (see `tick` case 2); before starting another card the working tree is clean and `<defaultBranch>` is checked out.
- **Never call `set_active_board`.** Verify the board as in `/trello-next` Step 1a.
- **Every comment the pipeline writes starts with `🤖 trello-pipeline ·`** (the "bot marker"). The bot and the user share one Trello token, so the marker is the only way to tell their comments apart. Comments are German.
- **Never guess at a decision.** A failure or gate is decided automatically only by the decide agent (see Triage), and only for a feasible option. If none is feasible, block the card and wait for the user (see Blocking).
- **Keep every Trello comment short (under ~1500 characters).** `add_comment` sends the text in the request and the API rejects long comments with error 414. Put the details into `.plans/.review-NN.md` / `.plans/.triage-NN.md` and reference them; on a 414, shorten and retry once.
- **Reports and cards stay honest:** a criterion without evidence is not met.
- Browser automation is always **headless**.
- Project rules (`CLAUDE.md`, hooks, "red check → change the code, not the rule") apply to every subagent unchanged.

## Plan file = card attachment (canonical)

`.plans/` is gitignored and lives on one machine, so every card carries its plan as an attachment. **The attachment is the canonical source; `.plans/NN-<name>.md` is a local cache.**

- Attachment name = the file's basename (`NN-<name>.md`; the index card carries `00-<name>.md`). Exactly one attachment per name per card.
- Upload (multipart `curl`, not base64 through MCP), from any cwd:
  `bash .claude/scripts/trello-attach.sh <cardId> .plans/NN-<name>.md NN-<name>.md --replace`
  Prints the attachment id; exit 1 on error. `--replace` deletes older attachments of the same name.
- Download: `bash .claude/scripts/trello-attachment-get.sh <cardId> NN-<name>.md .plans/NN-<name>.md`
  Exit 0 written · 2 no such attachment (local file untouched) · 1 error.
- If the project has no `.claude/scripts/trello-attach.sh` / `trello-attachment-get.sh`, install them with the trello-next `install.sh` (they land in `~/.claude/scripts/`), then symlink or copy them into the project's `.claude/scripts/` next to `trello-env.sh` (see the README). Called from the project root they work from anywhere; `TRELLO_PROJECT_ROOT` overrides the project root.
- **No agent edits the local plan copy.** The implementer writes its own working plan to `.plans/<branch>.md`, as before. A plan change goes in only through `plan-push NN`.
- **Plan sync** runs before every agent start for card NN (implement, fix, code review, acceptance, merge, triage): download the card's attachment over `.plans/NN-<name>.md` (and the index card's over `00-*.md`). Exit 2 and a local file exists → upload it (catch-up for a failed upload). Neither exists → block the card with the bot comment `🤖 trello-pipeline · Plan-Datei fehlt` and the `Blockiert` label.

## Shared setup (all modes except `status` without state)

### S1 — Board and lists

Follow `/trello-next` Step 1a (resolve `projectBoardId` from `.claude/trello-home/.trello-mcp/config.json`, compare with `get_active_board_info`, abort on mismatch; save `projectBoardIdLong`) and Step 1b (`get_lists`, `.claude/trello-lists.json`, aliases). Resolve four roles:

| Role | Source |
|------|--------|
| `todo` | as in `/trello-next` |
| `inProgress` | as in `/trello-next` |
| `review` | as in `/trello-next` ("Zum Testen" via `trello-lists.json`) |
| `done` | key `done` in `trello-lists.json`, else name alias "Fertig", "Done", "Erledigt" (case-insensitive) |

If `done` or any other role cannot be resolved, show all list names and ask with `AskUserQuestion`.

### S2 — Blocked label

`get_board_labels`; use the label named `Blockiert`. If missing: `create_label` name `Blockiert`, color `red`. Save its id as `blockedLabelId`.

### S3 — Git mode

```bash
git remote
cat .claude/git-config.json
```

- `remote` empty → **local mode**: no fetch, no push, no `/git-new` or `/git-done`. Branches are made locally by the implementer and merged locally by the merge agent.
- `remote` present → **remote mode**: `/git-new <branch>` in the implementer, `/git-done` in the merge agent.

**The implementer never merges.** The merge into the default branch happens only after the review passed (acceptance agent) and only by the merge agent (stage 3), so the default branch only ever contains reviewed code and history stays linear (rebase + `--ff-only`).

Save `defaultBranch` (from `git-config.json`, else `git symbolic-ref --short HEAD` on first run) and `gitMode` in the state file.

## State file `.plans/.trello-pipeline.json`

Written by the orchestrator only. Create `.plans/` if missing. Read it before every action, write it after every change.

```json
{
  "boardIdLong": "…",
  "lists": { "todo": "…", "inProgress": "…", "review": "…", "done": "…" },
  "blockedLabelId": "…",
  "defaultBranch": "master",
  "gitMode": "local",
  "indexCardId": "…",
  "maxFailedReviews": 3,
  "lastTickAt": "2026-10-24T20:15:00Z",
  "cards": {
    "01": {
      "title": "Commit data layer",
      "plan": ".plans/01-commit-data-layer.md",
      "cardId": "…",
      "url": "https://trello.com/c/…",
      "model": "opus",
      "dependsOn": [],
      "branch": null,
      "baseCommit": null,
      "headCommit": null,
      "reviewedCommit": null,
      "mergedCommit": null,
      "status": "todo",
      "reviewStage": null,
      "agentId": null,
      "blockCommentId": null,
      "failedReviews": 0,
      "triageDone": false,
      "triageStage": null,
      "triageSource": null,
      "autoAttempts": 0,
      "autoDecideCommentId": null
    }
  }
}
```

`status` is one of: `todo` · `implementing` · `review` · `reviewing` · `triaging` · `blocked` · `done`.
`reviewStage` (only while `reviewing`): `code` (code-reviewer agent) → `verify` (acceptance agent, opus) → `merge` (merge agent, sonnet).
`triageStage` (only while `triaging`): `solve` (solvability agent) → `source` (source-finder agent, only if data/content is missing) → `decide` (decide agent, only if a failure is still `human`; always first for a gate). `triageSource`: `review` (failed review) or `gate` (implementer decision gate). `triageDone`: triage has run for the current failure (reset to `false` whenever a review fails; a missing field counts as `false`). `autoAttempts`: automatic fix runs triggered by triage (including automatic decisions) for this card (max 2; reset to 0 when the card reaches Fertig or the user comments an instruction). `autoDecideCommentId`: id of the bot comment `Triage: automatisch entschieden und behoben`; the user may veto the decision with a comment newer than it until the card is merged (see `tick` case 3; reset to `null` when the card reaches Fertig or the veto was taken).
`maxFailedReviews`: failed reviews per card before the loop stops and asks (see "Blocking"); missing = 3. Set it per project by hand.
`lastTickAt`: UTC time of the last `tick` start (the heartbeat). A value younger than 20 min means a loop of this project is running; missing = no loop.
`headCommit` = branch tip after the implementer; `reviewedCommit` = branch tip of the last failed review (basis of the delta review in later rounds, `null` before the first failure); `mergedCommit` = default-branch tip after the fast-forward merge (set only after a passed review).

## `status`

Read-only. If the state file is missing: say "No pipeline state — run `/trello-pipeline setup`" and stop. Otherwise print a table: NN · title · status · actual Trello list (via `get_card`, one call per card in parallel) · blocked? · last bot comment (first line). Change nothing.

## `setup [NN-MM]`

### 1. Read the plans

Glob `.plans/[0-9][0-9]-*.md`; apply the range if given (default: all). Sort ascending by NN.

If the glob is empty: look for cards named `NN – …` on the board (`get_cards_by_list_id`, all four lists). Cards found and no state file → run **Restore** and stop. No plan files and no such cards → stop with "Keine Plan-Dateien gefunden (weder `.plans/` noch Board)".

For each file read it and extract:

- **Title**: from the first heading `# NN – Title` (strip the number prefix); fall back to the filename.
- **Model**: from a `Model: …` field in the file's `Status:` line; else from the status table in `00-*.md`; else `opus`.
- **Depends on**: same two sources; `–` means none. Store as an array of two-digit strings.

### 2. Idempotency

Load the state file if it exists. Fetch the cards of all four lists (`get_cards_by_list_id`, in parallel; archived cards are ignored). Treat a card as existing if the state file has its `cardId` **or** a card named `NN – …` exists on the board. Skip existing cards (but add them to the state file if missing). Running `setup` twice must create nothing.

For every existing card, check its attachments (`get_card`): no attachment named after the plan file → upload the local file (backfill). Attachment present → never overwrite it; if the local copy differs (download to the scratchpad, `cmp`), report "lokale Änderung nicht übernommen — `plan-push NN`".

### 3. Create cards 01…NN in `todo`

Create them **sequentially in ascending order** with `add_card_to_list` (so `pos` keeps the order; do not use the batch tool):

- **name**: `NN – <Title>`
- **description**:

  ```markdown
  **Plan:** Anhang `NN-<name>.md` (kanonisch; lokale Kopie `.plans/NN-<name>.md`)
  **Modell:** <model> · **Abhängig von:** <01, 02 | –>

  ---

  <full plan Markdown, with the first `# …` heading removed>
  ```

  The plans already contain `## Problem`, `## Goal`, `## Scope`, `## Acceptance Criteria`, so `/trello-next` Step 4c finds all four sections. If a plan lacks any of them, the implement subagent adds them (see its prompt). Trello limits descriptions to 16384 characters: if longer, cut at a paragraph boundary and append `…(gekürzt — vollständig im Anhang NN-<name>.md)`.

**Right after each card is created, upload its plan file** (see "Plan file = card attachment"); the full file is attached, so the truncated description loses nothing. An upload failure is a warning, not an abort: the next tick's plan sync catches up.

Save each card in the state file immediately after creation (`status: "todo"`).

### 4. Index card (plan `00`)

If `00-*.md` is in range, create one card in **`inProgress`**:

- name: `00 – <Title>` (e.g. "00 – Overview …")
- description: the plan Markdown (truncate as above); upload `00-*.md` as its attachment as well
- `create_checklist` named `Aufgaben`, then one `add_checklist_item` per created task card: `NN – <Title> — <card URL>`

Save `indexCardId`. Plan 00 is **never implemented** — it is the index/protocol card. It moves to `done` only when every other card is done.

If `00` is not in range and no index card exists, skip this.

### 5. Report and start the loop

Show a table of created cards (NN, title, model, depends on, URL). Then, unless called as `setup` only, go to **Start the loop**.

## `plan-push NN`

Replaces the canonical plan of card NN with the local file. Refused while an agent is running on NN (`agentId` set) or if NN is not in the state file.

1. `bash .claude/scripts/trello-attach.sh <cardId> .plans/NN-<name>.md NN-<name>.md --replace`
2. Refresh the card description (header + plan, truncated as in setup step 3) via `update_card_details`.
3. Bot comment `🤖 trello-pipeline · Plan aktualisiert`.

## Restore

For a machine without `.plans/` (or without the state file). Never invents a plan.

1. S1–S3 (board, lists, label, git mode).
2. `get_cards_by_list_id` for all four lists; take cards whose name matches `^\d\d – `. For each, `get_card` and download its `NN-*.md` attachment to `.plans/`. A card without such an attachment is reported and left out; the user decides.
3. Rebuild `.plans/.trello-pipeline.json`: `title`, `cardId`, `url` from the card; `model` and `dependsOn` as in setup step 1; `status` from the resync table; `branch` = `git branch --list "*-<first 8 chars of cardId>"` with `headCommit` its tip (else `null`); everything else `null`/`0`/`false`. `indexCardId` = the `00 – …` card; `lists`, `blockedLabelId`, `defaultBranch`, `gitMode` from S1–S3.
4. Show the overview table as in setup step 5. Do not start the loop; the user decides.

## Start the loop

**Heartbeat check first.** If `lastTickAt` in the state file is younger than 20 min, another session of this project runs the loop: do not start; tell the user (start anyway only if the user confirms that no other session runs). Otherwise clear every `agentId` in the state file: it belongs to a session that is gone, and the resync of the first tick treats its card as interrupted (`implementing`/`reviewing` with no agent → resync as in the table, `inProgress` → `todo`, resumed by a new implement subagent).

Invoke the Skill tool: `skill: "loop"`, `args: "/trello-pipeline tick"` (no interval → dynamic, self-paced). Tell the user the loop is running and how to stop it (`ScheduleWakeup stop`, or ask you).

**Whenever the loop ends** (every `ScheduleWakeup { stop: true }`, also when the user asks to stop), set `lastTickAt` to `null` first, so the watcher and other sessions see at once that no loop runs.

## `tick` — one loop step

First write `lastTickAt` (current UTC time, ISO 8601) to the state file — in every tick, case 1 included; it is the heartbeat the watcher and other sessions check. Then run S1 and S3 quickly (board check, list ids; use cached values from the state file for the rest), then **resync**:

For every card in the state file call `get_card` (parallel) and update `status` from reality, **except** `implementing`/`reviewing` (owned by a running agent):

| Trello state | status |
|--------------|--------|
| in `done` list | `done` |
| has `Blockiert` label | `blocked` |
| in `review` list | `review` |
| in `inProgress`, no agent running | `todo` (interrupted run — will be resumed by a new implement subagent) |
| in `todo` | `todo` |

Before starting any agent for a card, run its **plan sync** (see "Plan file = card attachment").

Then take the **first** case that matches:

1. **An agent is running** (`agentId` set on any card, no completion notification yet) → do nothing. `ScheduleWakeup` 600 s, `noop: true`, reason "subagent running; its completion notification wakes the loop sooner". (The completion notification re-invokes you — handle it with "When a subagent finishes".)
1a. **A card needs triage** (lowest NN first): `status: triaging` → continue at its `triageStage`; or `status: blocked` with `failedReviews ≥ 1` and `triageDone` false/missing (a failed review that was blocked before triage existed) → set `status: triaging`, `triageStage: "solve"`; or `status: blocked` with `triageDone` true, `triageSource` `review`/`gate` and at least one open (`human`) item in `.plans/.triage-NN.md` without a `T3:` line (the orchestrator skipped the decide agent) → set `status: triaging`, `triageStage: "decide"`. Run the **Triage** section below. Do not start any other card meanwhile.
2. **A blocked card exists** (lowest NN first; `triageDone` is true, or the block came from an implementer gate or rebase problem):
   - `get_card_comments`. Find comments **without** the bot marker that are **newer** than the comment with id `blockCommentId`.
   - None → tell the user once (not every tick; also `PushNotification` if available): "Card NN is blocked — please comment your instruction on <url>." Then **do not stop**: continue with case 3 and case 4 for other cards (their `dependsOn` are all `done`, so none depends on the blocked card). Only if neither case has anything to start: `ScheduleWakeup` 300 s, `noop: true`, reason "blocked on NN — waiting for user comment; nothing else ready". **Headless** (see "Headless mode"): end the loop instead (`ScheduleWakeup { stop: true }`); the watcher starts a new run when the comment comes.
   - Found → remove the `Blockiert` label (`update_card_details` with the label ids minus `blockedLabelId`), take the newest non-bot comment as the **instruction**, set `autoAttempts: 0`, `status: implementing`, and start an **implement subagent in fix mode** (below).
3. **A card is in `review`** (lowest NN) → first the **veto check**: if `autoDecideCommentId` is set, `get_card_comments`; a comment **without** the bot marker newer than that comment is a veto. Then do not start the acceptance or merge agent: set `autoDecideCommentId: null`, `autoAttempts: 0`, `failedReviews` unchanged, `status: implementing` and start an **implement subagent in fix mode** with that comment as the instruction (as in case 2; the card goes back through all review stages afterwards). No veto → continue. The review has two stages, run one after the other:
   - `reviewStage` null → set `status: reviewing`, `reviewStage: "code"`, start the **code-review subagent** (stage 1).
   - `reviewStage: "code"` and its report is saved → set `reviewStage: "verify"`, start the **acceptance subagent** (stage 2, verify only).
   - `reviewStage: "verify"` and its report is saved to `.plans/.verify-NN.md` (it reported `RESULT: passed`) → set `reviewStage: "merge"`, start the **merge subagent** (stage 3).
4. **Next card**: the lowest NN with `status: todo` whose `dependsOn` are all `done` → set `status: implementing`, start the **implement subagent** (normal mode). If `todo` cards exist but none has its dependencies met, that means a dependency is stuck: stop and report (headless: end the loop with `ScheduleWakeup { stop: true }`; the watcher log shows the state).
5. **Everything except the index card is `done`** → move the index card to `done`, add a bot comment "Alle Aufgaben erledigt", tick any remaining checklist items, run `bash ~/.claude/scripts/trello-pipeline-watch.sh off "$PWD"` (removes this project's watcher; nothing happens if it is off), and end the loop with `ScheduleWakeup { stop: true }`. Summarize to the user.

### When a subagent finishes

Read its final report. It must contain a line `RESULT: review | passed | blocked | done | failed` plus details (`passed` only from the acceptance agent, `done` only from the merge agent). Then:

- Clear `agentId`; store `branch`, `baseCommit`, `headCommit`, `mergedCommit`, `blockCommentId` if reported.
- `review` (implement finished) → `status: review`, `reviewStage: null`. `passed` (acceptance agent) → save its evidence to `.plans/.verify-NN.md`, keep `status: reviewing`, `reviewStage: "verify"` (next tick starts the merge agent). `done` (merged by the merge agent) → `status: done`, `reviewStage: null`. `blocked` → if it came from a failed review (acceptance or merge agent with a `FAILURES:` block listing items): `failedReviews += 1`, `reviewedCommit` = the branch tip it checked, save its report as `.plans/.verify-NN.md` (evidence for the delta re-check), `triageDone: false`, `triageSource: "review"`, save the `FAILURES:` block to `.plans/.triage-NN.md` (section "Failures"), `status: triaging`, `triageStage: "solve"`, `reviewStage: null`, and run **Triage** now; if it came from an implementer decision gate (implement agent, comment `Entscheidung nötig`): `triageDone: false`, `triageSource: "gate"`, save the gate comment (question, options, recommendation) to `.plans/.triage-NN.md` (section "Gate"), `status: triaging`, `triageStage: "decide"` (skip `solve`/`source`), and run **Triage** now; otherwise (rebase/merge problem, `FAILURES: none`) `status: blocked`, `reviewStage: null`, `triageDone: true`.
- The **code-review subagent** (stage 1) returns a plain report, not a `RESULT:` line: save it to `.plans/.review-NN.md` and keep `status: reviewing` (next tick starts stage 2). If it returns nothing, treat as `failed`.
- `failed` or no parsable RESULT → comment on the card (`🤖 trello-pipeline · Agent ohne Ergebnis beendet: <reason>`), add `Blockiert` label, `status: blocked`, store that comment id. Never retry silently.
- Run the next tick immediately (do not wait for the wakeup).

## Implement subagent

Spawn with the Agent tool: `subagent_type: "general-purpose"`, `model` = the card's model (`opus` or `fable`; default `opus`), `description: "Task NN <title>"`. Save the returned agent id in `agentId`. Prompt (fill the placeholders):

```
You implement Trello card "<NN – title>" (<cardUrl>, id <cardId>) in /<project dir>.
Plan file: <plan path>. Mode: <normal | fix>.
<fix mode only: Instruction from the user (comment on the card): "<text>". Previous review/blocker comment: "<text>".>
<fix mode from triage only (no user comment; the pipeline decided this itself): Instruction from triage, NOT from
 the user: fix exactly these failures / carry out exactly this decision: <failures + chosen fix, and for decided
 options the option id and reason, from .plans/.triage-NN.md>. Sources found for missing
 data/content: <paths/URLs/tables and how to import them, or "none needed">. You may use these sources; polite GETs
 on the live site only (`liveUrl` in `.claude/dev-config.json`; throttled, GET only, no login, no forms, no writes to
 live, no licensed or large downloads); credentials never into code. Do not widen the scope beyond the listed failures. If you find the
 failures cannot be fixed as described, do not improvise: raise a decision gate.>

Do NOT edit <plan path>: it is a local copy of the card's canonical attachment (plan changes go through the user
via `plan-push`).
FIRST read CLAUDE.md of the project and .plans/00-*.md (if present). Follow CLAUDE.md without exceptions —
including its pre-commit checks (e.g. /simplify, /security-review, make ci). A red check means changing the
code, never the rule. In local mode (no remote) the /security-review skill cannot run (it needs origin/HEAD):
do the review by hand with the checklist CLAUDE.md names (e.g. the vibesec skill) over `git diff HEAD` and say so
in the card comment. Keep Trello comments under ~1500 characters (longer ones fail with error 414).

Run the /trello-next flow in AUTOPILOT mode for this card. Overrides to its steps:
- Step 1: as written (verify board, lists, user). Never call set_active_board.
- Steps 2-3: skip. The card is given. Assign yourself to it if unassigned.
- Step 4/4b: fetch the card normally. Step 4c: if Problem/Goal/Scope/Acceptance Criteria are missing, generate
  and push them WITHOUT asking.
- Step 5: branch name as in trello-next (fix-/feature- + slug + first 8 chars of card id).
- Steps 6-9: NO plan mode and no approval gate. The plan is <plan path>. Write .plans/<branch>.md in the
  trello-next plan format (header + card description + the plan's steps as checkboxes) so /spec and /tdd find it.
  In fix mode, add the instruction as an extra step.
- Step 10: move the card to "<inProgress name>", write .claude/trello-active-card.json.
- Step 11: always "Start implementing" without asking: /spec -> branch -> /tdd -> /qa-report. Use each skill's
  documented defaults instead of AskUserQuestion; run browsers headless; do not upload to Trello unless the
  qa-report step does so without asking.
- Git (<gitMode>). YOU NEVER MERGE into <defaultBranch> — the merge happens only after the review passed.
    local  -> no fetch, no push, no /git-new, no /git-done.
              normal mode: `git checkout -b <branch> <defaultBranch>`.
              fix mode:    `git checkout <branch>` and keep working on the existing branch.
    remote -> normal mode: /git-new <branch>. fix mode: `git checkout <branch>`. Never run /git-done.
    Commit only on <branch>. Do NOT delete the branch. At the end the working tree must be clean
    (gitignored files aside) and <branch> checked out, so the reviewer can start from it.
- Record `baseCommit` (<defaultBranch> tip when you started) and `headCommit` (<branch> tip when you finish).

SELF-CHECK before you hand over (the independent review runs the same checks; every finding it makes costs a
full extra round of about 30-40 minutes):
- Check every acceptance criterion with evidence, and run `make ci` (or the project's equivalent) once at the end.
- Test quality: each new test that guards a rule must be shown to go red (mutation check: break the rule, test red,
  restore, `git diff` empty). No fixed dates that will expire (use dates relative to today). Add negative asserts
  where the plan says "must not".
- Review your own diff with the stage-1 reviewer prompt below (`feature-dev:code-reviewer`, input `git diff
  <defaultBranch>..<branch>`) and fix every confirmed high/medium finding.
- Test data: before E2E/manual runs note the max ID (or a marker such as `e2e-…@beispiel.de`) of every table you
  write to. Afterwards delete exactly your own rows in the LOCAL dev database (`SELECT COUNT` before and after,
  limited by ID range/marker); never other rows, never outside the local dev DB. List this in your comment.

When finished and all acceptance criteria are met with evidence:
1. Move the card to "<review name>" (id <review list id>) with boardId <boardIdLong>.
2. Add ONE comment starting with "🤖 trello-pipeline · Umsetzung fertig": summary, commit hashes, and every
   acceptance criterion with its evidence (command + result). Deferred items and open points listed explicitly.

DECISION GATE / QUESTION / RED CHECK YOU CANNOT FIX: do not guess and do not work around it. Add a comment
starting with "🤖 trello-pipeline · Entscheidung nötig" with the question, the options in a fixed format
(`O1 …`, `O2 …`, each with steps, effect, reversible yes/no) and `Empfehlung: O<n>, weil …`, add the label id <blockedLabelId> to the card (keep the card in "<inProgress name>"),
commit any unfinished work as a `WIP:` commit on <branch>, leave the working tree clean and in a described, consistent state, `git checkout <defaultBranch>`, and stop.

FINAL REPORT (plain text), first line exactly one of:
RESULT: review     (implemented on the branch, card in review list, NOT merged)
RESULT: blocked    (gate hit; include BLOCK_COMMENT_ID: <id>)
RESULT: failed     (could not continue; say why)
Then: BRANCH, BASE_COMMIT, HEAD_COMMIT, summary, each acceptance criterion with evidence, deferred items.
```

## Review (three agents, one after the other)

Never the implementer. Both run against the **branch**, which is not yet merged.

### Stage 1 — code-review subagent (read-only)

`feature-dev:code-reviewer` has no Bash and no Trello access, so the orchestrator prepares the input first:

```bash
git checkout <branch>
git diff --stat <defaultBranch>..<branch>   > .plans/.review-NN.diff
git diff <defaultBranch>..<branch>         >> .plans/.review-NN.diff
```

**Delta review (round 2 and later, `reviewedCommit` set):** the diff file holds only `git diff <reviewedCommit>..<branch>` (the fix), and the prompt adds: "This is a re-review after a fix. The earlier findings are in the previous `.plans/.review-NN.md`; check that they are fixed and look for new problems in the fix diff only." Keep the previous report as `.plans/.review-NN.prev.md`.

Spawn: `subagent_type: "feature-dev:code-reviewer"`, `description: "Code review NN <title>"`. Prompt:

```
Review the changes of Trello card "<NN – title>" in /<project dir>: the diff is in .plans/.review-NN.diff
(branch <branch> against <defaultBranch>); you may read any file in the repo. Read-only — change nothing.
Check against the plan file <plan path> (scope, acceptance criteria) and the project's CLAUDE.md: correctness
bugs, security, every rule CLAUDE.md names (docblocks, namespaces/file conventions, wrappers that all network
access must go through, language and umlaut rules, commit-message rules — `git log <defaultBranch>..<branch>`),
ignored or weakened checks (suppression comments, skipped tests, changed rule files without the commit-title
suffix CLAUDE.md demands), credentials in code, scope creep. Report each finding as: file:line · severity (high/medium/low) · confidence (high/medium/low) ·
what is wrong · concrete failure scenario. Only report findings you are confident about; no style nits.
```

Save its report to `.plans/.review-NN.md` (the orchestrator writes it; the agent is read-only). `.plans/` is gitignored.

### Stage 2 — acceptance subagent (verify only, never merges)

Spawn: `subagent_type: "general-purpose"`, `model: "opus"`, `description: "Verify NN <title>"`. Fresh agent. Prompt:

```
You verify Trello card "<NN – title>" (<cardUrl>, id <cardId>) in /<project dir>, branch <branch> (NOT yet merged
into <defaultBranch>). You do NOT implement, fix or merge anything and you do not trust the implementer's report:
verify yourself.
Inputs: plan file <plan path> (acceptance criteria), the branch commits <defaultBranch>..<branch> (<reviewedCommit: <hash> | none>), the
code-review report .plans/.review-NN.md, the card's comments (get_card_comments, including earlier reviews and
user instructions).

Steps:
1. `git checkout <branch>`. Read CLAUDE.md, the plan file, the card and the code-review report. List every
   acceptance criterion.
2. Check each criterion yourself with evidence: run `make ci` (or the project's equivalent from CLAUDE.md),
   the relevant tests, curl / headless Playwright (never headed), `git show --stat`, read the diff.
   A criterion marked "deferred" counts as met only if the plan allows that deferral and it is documented.
3. Weigh the code-review report: re-check each high/medium finding yourself. A confirmed correctness, security
   or CLAUDE.md-rule finding fails the review; low-confidence findings and nits do not.
4. If the card holds earlier user instructions, verify they were carried out.
4a. Delta (only when <reviewedCommit> is given, i.e. this is a re-check after a fix): always re-check the failed
   items and run `make ci`. Re-check an acceptance criterion only if `git diff <reviewedCommit>..<branch> --stat`
   touches files its evidence depends on; for the others reuse the evidence of the earlier verify report
   `.plans/.verify-NN.md`, and say so in your report.
5. Test data: note the max ID/marker of every table you write to before E2E runs; afterwards delete exactly your
   own rows in the local dev DB (`SELECT COUNT` before and after) and report it. Leftover rows of the implementer
   are not a failure by themselves: delete them if the ID range/marker proves they are the pipeline's own.

NOT PASSED -> change no code, do not merge. `git checkout <defaultBranch>`. Add a comment starting with
"🤖 trello-pipeline · ❌ Prüfung nicht bestanden": each failing criterion/finding with file:line and evidence, and
the sentence "Bitte Anweisung als Kommentar hinterlassen — die Pipeline wartet." Add label id <blockedLabelId>,
move the card to "<inProgress name>". Then end your report with a machine-readable block (one line per
failing criterion or confirmed finding; the orchestrator hands it to the triage agents):
FAILURES:
- F1 · type: code|data|content|env|decision · criterion/finding · file:line · evidence · what would fix it
  type = code (fixable in the repo) · data or content (rows, files, texts are missing, not wrong) ·
  env (a tool, service or credential is not available) · decision (needs a product/owner decision).

PASSED -> change nothing (no merge, no card move, no comment). `git checkout <defaultBranch>`.

FINAL REPORT, first line exactly one of:
RESULT: passed    (all criteria met; include BRANCH_TIP: <hash of <branch>>; the orchestrator saves your report as
                  the merge agent's input, so give evidence per criterion: command + result)
RESULT: blocked   (failed; include BLOCK_COMMENT_ID: <id of your comment> and the FAILURES: block above)
RESULT: failed    (verification could not be completed; say why)
Then: evidence per criterion and the findings.
```

### Stage 3 — merge subagent (mechanical, sonnet)

**Inline merge (no agent):** if `git merge-base --is-ancestor <defaultBranch> <branch>` is true (the rebase would be a no-op), the orchestrator does steps 0, c, d and e itself (verify the tip, ff-merge, bookkeeping) without spawning an agent; steps a and b are skipped. Otherwise the merge agent runs as described here.

Runs only after stage 2 reported `RESULT: passed`. Spawn: `subagent_type: "general-purpose"`, `model: "sonnet"`, `description: "Merge NN <title>"`. Fresh agent. It does not re-verify: it merges what stage 2 accepted and does the Trello bookkeeping. Prompt:

```
You merge the verified Trello card "<NN – title>" (<cardUrl>, id <cardId>) in /<project dir>, branch <branch>,
into <defaultBranch>. The acceptance agent already passed it: evidence is in .plans/.verify-NN.md, it accepted
branch tip <BRANCH_TIP>. You do NOT verify, implement or fix anything and never force-push. Stop at the first
problem and report it; do not improvise a workaround.

Steps:
0. `git rev-parse <branch>` must equal <BRANCH_TIP>. Otherwise stop: RESULT: blocked, FAILURES: none, comment
   "Branch nach der Prüfung geändert".
a. local:  `git checkout <branch>`; `git rebase <defaultBranch>`. remote: `git fetch origin` first, rebase onto
   origin/<defaultBranch>.
b. On conflict `git rebase --abort` and BLOCKED (comment "Rebase-Konflikt" with the conflicting files, add label id
   <blockedLabelId>, move the card to "<inProgress name>"). If the rebase rewrote commits cleanly (hashes differ),
   run `make ci` (or the project's equivalent from CLAUDE.md) again; red = BLOCKED with a comment "make ci nach
   Rebase rot" and a FAILURES: block (type: code, file:line, evidence from the output), label and card move as
   above. Hashes unchanged -> no re-run.
c. local:  `git checkout <defaultBranch>`; `git merge --ff-only <branch>`; no push.
   remote: `git checkout <defaultBranch>`; `git merge --ff-only <branch>`; then `git push` as /git-done does.
   If `--ff-only` fails, do not create a merge commit: BLOCKED with a comment (label, card move as above).
d. Keep the branch (do not delete it). Record `mergedCommit` = `git rev-parse <defaultBranch>`.
e. Move the card to "<done name>" (id <done list id>, boardId <boardIdLong>); add a comment starting with
   "🤖 trello-pipeline · ✅ Geprüft und gemergt" with the evidence per criterion (short, from .plans/.verify-NN.md)
   and the merged commit; tick this card's item on the index card's checklist "Aufgaben" (<indexCardId>,
   `update_checklist_item`); in .plans/00-*.md change this task's status-table row from ☐ to ✅ (only that cell).
   .plans is gitignored.

FINAL REPORT, first line exactly one of:
RESULT: done      (merged, card in done list; include MERGED_COMMIT: <hash>)
RESULT: blocked   (rebase/merge problem or red ci; include BLOCK_COMMENT_ID: <id of your comment>; for red ci the
                  FAILURES: block with items, for a rebase/merge problem write FAILURES: none)
RESULT: failed    (could not complete; say why)
```

## Triage (after a failed review)

Runs when the acceptance agent (or the merge agent, on red `make ci` after the rebase) failed a card (card is in "In Arbeit" with the `Blockiert` label, branch unmerged) — directly after its report, or from `tick` case 1a for a card that was blocked before triage existed. Goal: decide whether the failure or gate can be fixed or decided **without the user**, and if so do it automatically. Also runs for an implementer decision gate (`triageSource: gate`, starts at stage `decide`). Never for a rebase/merge problem or an agent that returned no result — those wait for the user.

**Never skip the stages.** The orchestrator never sets an item to `human` itself, and never writes a verdict like "no agents, product decision, human". Only the decide agent's result (`decided=none`, confidence low, or no usable result) makes an item `human`. Every item that is not `auto` after `solve`/`source` (including `type: decision` items and items the solve agent had to answer `solvable_alone: no` for) goes to `decide`.

Strictly **one agent at a time**, all triage agents are **read-only** (they cannot Edit/Write; the orchestrator writes their reports to `.plans/.triage-NN.md`). Triage agents never touch the card or the repo; a gate is decided only by the decide agent, under the feasibility rules below.

**Input.** `.plans/.triage-NN.md` section "Failures" (the `FAILURES:` block of the acceptance or merge agent). If that section is missing (legacy block), build it yourself from the bot's `❌ Prüfung nicht bestanden` comment on the card (`get_card_comments`) and `.plans/.review-NN.md`, assigning a `type` to each item.

### Fast path (no agents)

If every failure is `type: code`, has a concrete "what would fix it" (file:line and steps) and touches none of the hard limits (decide rule 4: credentials, licensed or customer files, rule files, shared base code, live writes, data deletion), skip `solve`, `source` and `decide`: write the verdict table (`auto` for all, reason "Fast path: code failure with a concrete fix") to `.plans/.triage-NN.md` and go straight to the action under **Verdict and action**. The fast path only ever leads to `auto`. Any doubt (a `data`/`content`/`env`/`decision` item, a fix that is vague or touches a rule file, shared base code or data deletion) → run the stages as usual, never jump to `human`. `autoAttempts` still limits it.

### Stage `solve` — solvability agent

Set `triageStage: "solve"`. Spawn `subagent_type: "Plan"`, `model: "opus"`, `description: "Triage solve NN <title>"`. Prompt:

```
Triage failed Trello card "<NN – title>" (<cardUrl>) in /<project dir>, branch <branch> (unmerged; read it with git,
do not check anything out that changes the working tree). You are read-only: change nothing.
Inputs: plan file <plan path>, the review report .plans/.review-NN.md, the failures in .plans/.triage-NN.md
(section "Failures"), CLAUDE.md, the card comments.
For EACH failure answer:
  solvable_alone: yes | no   — can an implementer fix it on this branch without asking the user?
  fix: concrete steps and files (no code dumps)
  missing_data: yes | no     — is something absent (rows, files, texts) rather than wrong?
  blocker: if no, what exactly stops it
You MUST answer solvable_alone: no for: licensed or customer-supplied files (e.g. commercial fonts),
credentials or secrets, changes to the rule files CLAUDE.md names (linter/static-analysis config, test config,
build file, architecture tests) or anything CLAUDE.md says needs the user's approval, any change inside code the
project must not modify (vendored or shared base code, as CLAUDE.md says), product or owner decisions,
writes to the live site, deleting data (exception: rows the pipeline created itself in the local dev DB, proven by ID range, marker or time window). Do not guess: if the evidence is insufficient, answer no and say what is missing.
For each failure with solvable_alone: no also give `options:` (2-3 concrete options O1, O2, … each with steps/files,
effect, reversible yes/no) and `recommended: O<n> — why`.
End with one line per failure: `T1: <F-id> · solvable_alone=<yes|no> · missing_data=<yes|no>`.
```

Save the report to `.plans/.triage-NN.md` (section "Solve"). If any failure has `missing_data: yes` or `type: data|content` → set `triageStage: "source"` and continue; otherwise go to `decide` if any failure is not solvable alone or has `type: decision` (with the options the solve agent gave), else to the **Verdict**.

### Stage `source` — source-finder agent

Only for failures with missing data or content. Set `triageStage: "source"`. Spawn `subagent_type: "Explore"`, `model: "sonnet"`, `description: "Triage source NN <title>"`, thoroughness "very thorough". Prompt:

```
Find where the data or content missing for Trello card "<NN – title>" in /<project dir> can be obtained. Read-only:
change nothing, do not import or download anything yourself (report only).
Missing items: <the failures with type data|content or missing_data=yes, with evidence>.
Search in this order and stop at the first source that fully covers an item:
 1. this repo and .plans (importers, tasks, fixtures, app/data);
 2. the sources CLAUDE.md names: the old codebase, the old database or its dumps (read-only query or zcat/grep),
    sibling projects, and the local dev site (`devUrl` in `.claude/dev-config.json`);
 3. WebSearch / WebFetch for public documentation or assets;
 4. at most a few polite GETs on the live site (`liveUrl` in `.claude/dev-config.json`; throttled, GET only, no login, no forms, no writes to live,
    no licensed or large files, no more than ~10 requests).
For each missing item report: where the source is (path / URL / table), how it would be imported (reuse an existing
importer or task of the project, or the asset download of the plan that covers it), licence/privacy risk,
confidence (high/medium/low), and `found: yes | partial | no`. Credentials, licensed fonts and customer-supplied files
are never "found": report them as `found: no` with the reason.
End with one line per item: `T2: <F-id> · found=<yes|partial|no> · confidence=<h|m|l>`.
```

Save the report to `.plans/.triage-NN.md` (section "Sources"). If the agent has no web tool in this session, it must say so and continue local-only. Then go to `decide` if any failure is still not `auto`, else to the **Verdict**.

### Stage `decide` — decide agent

Runs for every failure that is still `human` after `solve`/`source`, and first for every gate (`triageSource: gate`). Set `triageStage: "decide"`. Spawn `subagent_type: "Plan"`, `model: "opus"`, `description: "Triage decide NN <title>"`. Prompt:

```
Decide for Trello card "<NN – title>" (<cardUrl>) in /<project dir>, branch <branch> (unmerged; read-only, change
nothing). Open items: <failures still human, or the gate> with their options and recommendation, in
.plans/.triage-NN.md (sections "Failures", "Solve", "Sources" or "Gate"). Also read the plan file <plan path>,
CLAUDE.md, .plans/.review-NN.md and the card comments (earlier user instructions win over everything).
For EACH item check the recommended option first, then the other options. An option is FEASIBLE only if all hold:
 1. it fully fixes the failure / answers the gate's question, inside the card's scope and plan;
 2. it follows CLAUDE.md and earlier user instructions on the card (including a durability check if CLAUDE.md
    defines one);
 3. it is reversible in the repo (no data deletion, no write to the live site, no step that cannot be undone);
 4. it is NOT one of: credentials or secrets, licensed or customer-supplied files, rule files or anything CLAUDE.md
    says needs the user's OK, vendored or shared base code, writes to the live site, deleting data (exception: rows the pipeline created itself in the local dev DB, proven by ID range, marker or time window).
    Product decisions (customer-visible texts, prices, legal texts, design, features, deliberate differences from an
    acceptance criterion) are NOT on this list: decide them too if the recommended option meets 1–3 and 5; the user
    can veto afterwards;
 5. it needs no input only the user has. If evidence is missing, it is not feasible; do not guess.
Answer per item: `decision: O<n> | none`, a one-line reason, `visible: yes | no` (does the decision change anything
a customer sees: texts, prices, legal texts, design, features), and concrete fix steps as an instruction for the
implementer (no code dumps). End with one line per item:
`T3: <F-id|GATE> · decided=<O<n>|none> · confidence=<h|m|l> · visible=<yes|no>`.
```

Save the report to `.plans/.triage-NN.md` (section "Decision"). If the agent returns nothing or nothing parsable: all open items stay `human`.

### Verdict and action

Per failure (write the verdict table into `.plans/.triage-NN.md`):
- **`auto`** = solve agent `solvable_alone: yes` **and** (`missing_data: no`, **or** source agent `found: yes` with confidence ≥ medium, no licence/credential issue and no extra manual step).
- **`auto-decided`** = not `auto`, but the decide agent has `decided=O<n>` with confidence ≥ medium.
- **`human`** otherwise (`decided=none`, confidence low, or no decide result).

Before the verdict: every `human` item needs a `T3:` line in `.plans/.triage-NN.md` (section "Decision"). If one is missing, run the `decide` stage first.

Set `triageDone: true`, `triageStage: null`, then:

- **All failures/items `auto` or `auto-decided` and `autoAttempts < 2`** → remove the `Blockiert` label (`update_card_details`), `autoAttempts += 1`, post one bot comment `🤖 trello-pipeline · Triage: automatisch entschieden und behoben` (German: the failures, the chosen fix, per decided item the option and its one-line reason, `⚠ kundensichtbar` when `visible=yes`, the sources used, attempt number; for a gate: `Entscheidung automatisch getroffen`; always the sentence `Veto bis zum Merge: Kommentar auf dieser Karte.`), store its id as `autoDecideCommentId`, send `PushNotification` (if available) when any decided item is `visible=yes`, set `status: implementing`, and start the **implement subagent in fix mode, triage variant** (see its prompt) with the decided options as instruction. After it reports `RESULT: review`, the review stages run again as usual.
- **Otherwise** (any `human`, or `autoAttempts ≥ 2`) → the card stays blocked. Post `🤖 trello-pipeline · Triage: Entscheidung nötig` (German) with, per failure: verdict, why no option is feasible, the options and a recommendation, so one comment from the user is enough; items that were `auto`/`auto-decided` are named as such, so only the open ones need an answer; store its comment id as `blockCommentId`; `status: blocked`. Tell the user once. The loop waits as in "Blocking".

`failedReviews` counts every failed review (including those that were fixed automatically); at `maxFailedReviews` (missing = 3) the loop stops and asks (below).

## Blocking (summary)

A card is **blocked** when it has the `Blockiert` label. While a card is in triage, `tick` starts nothing else; while a card is merely blocked (waiting for the user), `tick` keeps reviewing and implementing cards that do not depend on it, and the blocked card resumes first as soon as the user comments. After a failed review or an implementer gate the card first goes through **Triage**: solvable failures and feasibly decided options are carried out automatically (max 2 automatic attempts per card, `autoAttempts`); everything else waits. A blocked card resumes only when the user adds a comment **without** the bot marker, newer than `blockCommentId`; that comment is the instruction for the fix-mode implement subagent (and resets `autoAttempts`). An automatic decision can be vetoed the same way until the merge (a comment newer than `autoDecideCommentId`, checked in `tick` case 3 before the acceptance and merge agents). A failed review always goes back to "In Arbeit" with the label. **The branch stays unmerged**; the fix run continues on the same branch, returns the card to "Zum Testen", and all review stages (code, acceptance, merge) run again with fresh agents.

If the same card fails review **`maxFailedReviews` times** (`failedReviews` ≥ `maxFailedReviews`, missing = 3), stop the loop and ask the user directly with `AskUserQuestion` instead of looping further — automatic fixes included. **Headless:** no `AskUserQuestion`; post `🤖 trello-pipeline · <n>× nicht bestanden — bitte Anweisung kommentieren`, keep the `Blockiert` label, store the comment id as `blockCommentId`, `status: blocked`, `triageDone: true`, and go on with other cards. The next user comment resumes the card as in `tick` case 2.

## Headless mode

A run is headless when `printenv TRELLO_PIPELINE_HEADLESS` prints `1` (only the watcher sets it). Nobody reads the terminal, so:

- Never call `AskUserQuestion`. Where the skill would ask (role not resolvable, `maxFailedReviews` reached, a stuck dependency), block the affected card with a bot comment that states the question, or end the loop if no card fits, and let the log tell the rest.
- `tick` case 2 with nothing else to start and a stuck dependency end the loop instead of waiting; the watcher starts the next run.
- Everything else (one subagent at a time, triage, review stages, bot marker) is unchanged.

## Start from a comment (cron)

`~/.claude/scripts/trello-pipeline-watch.sh` (installed by `install.sh`) starts the pipeline without an open session. Per project, nothing is shared between projects:

```
/trello-pipeline watch on       # bash ~/.claude/scripts/trello-pipeline-watch.sh on "$PWD"
/trello-pipeline watch off      # … off "$PWD"
/trello-pipeline watch status   # … status "$PWD"
```

`watch on` adds one crontab line for this project (every 5 min, tagged `# trello-pipeline-watch <project root>`); `off` removes exactly that line. Every 5 min the script (no Claude cost unless it starts):

1. exits if `.plans/.trello-pipeline.lock` is held (a headless run is still going) or `lastTickAt` is younger than 20 min (a session runs the loop);
2. reads all cards of the board in one call — **Trello wins** over the state file (the `Blockiert` label and the list come from Trello; differences are logged);
3. starts `claude -p "/trello-pipeline"` headless (clean environment, no `ANTHROPIC_API_KEY`, `--permission-mode bypassPermissions`, 12 h timeout) when a blocked card has a comment without the bot marker newer than its block comment (or the label, if set by hand), a card has a veto comment newer than `autoDecideCommentId`, or a card is ready (review list, or todo/In Arbeit without the label and all `dependsOn` in Fertig);
4. turns itself off when every card, the index card included, is in Fertig.

Log: `.plans/.trello-pipeline-watch.log` (decisions, start, exit code, cost); the last run's JSON output: `.plans/.trello-pipeline-watch-run.json`. Mind: turning the watcher on with a ready card starts the pipeline within 5 minutes. On WSL, cron runs only while the WSL VM is up.

`watch on|off|status`: run the script with the mode and the project root, show its output. No board check needed.

## Error handling

| Situation | Action |
|-----------|--------|
| Active Trello board ≠ project board | Abort as in `/trello-next` Step 1a; never `set_active_board` |
| `done` list not resolvable | Ask with `AskUserQuestion`, offer to add `done` to `.claude/trello-lists.json` (headless: end the loop, no question) |
| `lastTickAt` younger than 20 min on start | Another session runs the loop: do not start, tell the user |
| Plan lacks Acceptance Criteria | Still create the card; the implement subagent generates them (4c, no gate) |
| Card creation fails midway | State file already holds the created cards; fix the cause and re-run `setup` (idempotent) |
| `get_my_cards` / list reads lag after `move_card` | Trust the state file and the `get_card` of that single card, not list listings |
| Subagent hits a decision gate | Triage stage `decide`: a feasible option is taken automatically (max 2 with `autoAttempts`), else card blocked + comment and the pipeline waits for the user |
| Review failed | Triage (solvability agent, source-finder if data/content is missing, decide agent for what is still open); solvable or feasibly decided → automatic fix on the same branch (max 2), else wait for the user |
| Orchestrator is tempted to skip `solve`/`decide` ("product decision, human") | Not allowed: run the stages; only the decide agent may set `human` |
| User vetoes an automatic decision (comment newer than `autoDecideCommentId`, before merge) | No acceptance/merge; fix mode with the comment as instruction |
| Triage or decide agent returns nothing / unusable | Verdict `human` for all open items; post the "Entscheidung nötig" comment with what is known |
| Subagent returns no `RESULT:` | Treat as `failed` (see "When a subagent finishes") |
| Dependency never becomes `done` | Stop and report which card is stuck |
| Plan upload fails (setup / backfill) | Warn, continue; the next tick's plan sync uploads the local file |
| No plan attachment and no local plan file | Block the card (`Plan-Datei fehlt` + `Blockiert`); never invent a plan |
| Local plan differs from the attachment | Attachment wins; report "lokale Änderung nicht übernommen — `plan-push NN`" |
| Restore finds a card without a plan attachment | Report it, leave the card out, the user decides |
