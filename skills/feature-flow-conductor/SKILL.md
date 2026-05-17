---
name: feature-flow-conductor
description: Top-level orchestrator for the agentic feature workflow. Reads/writes state.json, dispatches to stage skills, pauses at human checkpoints. Invoked by the /feature slash command.
---

# Feature flow conductor

You are the orchestrator for a 6-stage feature workflow. You do not implement code yourself — you dispatch each stage to a specialist skill or subagent and persist state to a JSON file so the workflow can be paused, resumed, and audited.

## Inputs

- `TICKET`: a tracker ticket ID (JIRA-style by default, e.g. `ABC-1234`; configurable in `.claude/commands/feature.md`).

## Workspace

For every run, the workspace is `.claude/features/<TICKET>/`. Create it if missing.

The single source of truth for progress is `.claude/features/<TICKET>/state.json`. Always read it before acting and write it after every meaningful step.

State schema (canonical JSON schema available at `${CLAUDE_PLUGIN_ROOT}/references/state-schema.json`):

```json
{
  "ticket": "ABC-1234",
  "branch": null,
  "stage": "brief",
  "stages": {
    "brief":      { "status": "pending", "asset": null },
    "plan":       { "status": "pending", "asset": null },
    "implement":  { "status": "pending", "tasks_completed": 0, "tasks_total": 0 },
    "pr":         { "status": "pending", "url": null, "number": null },
    "review_loop":{ "status": "pending", "round": 0, "max_rounds": 5, "rounds": [] }
  }
}
```

`status` ∈ `pending | in_progress | complete | failed`.

## Stages

Run each stage **as a fresh-context subagent** via the `Agent` tool (`subagent_type: general-purpose` unless noted). Pass only the minimum the stage needs — never the whole conversation. After the subagent returns, read its result, update state.json, and only then proceed.

### Stage 1 — gather + author brief (`brief`)

1. Invoke the `gather-requirements` skill in a subagent. Hand it the ticket ID.
2. The subagent returns a synthesized brief (markdown content).
3. Invoke the `feature-brief-author` skill in a subagent. Hand it the content + ticket ID. The subagent writes `brief.md` and posts the tracker comment.
4. Update state.json: `brief.status = "complete"`, `brief.asset = ".claude/features/<TICKET>/brief.md"`.

### ⏸ Human checkpoint 1

Stop and ask the human to review the brief. Use the `AskUserQuestion` tool with options: _Approved_, _Needs revisions_, _Cancel_. If revisions: re-invoke Stage 1 with the human's notes.

### Stage 2 — plan (`plan`)

1. Invoke a subagent with the `agent-skills:planning-and-task-breakdown` skill. (This skill is shipped by the `agent-skills` plugin — install `addyosmani/agent-skills` if you don't already have it, or substitute your own planning skill in this step.)
2. Hand it ONLY the path to `brief.md` and a directive to write tasks to `.claude/features/<TICKET>/tasks.md`.
3. Tasks file format: numbered list, each task with `## Task N: <title>`, acceptance criteria, dependencies. Sized to be implementable + verifiable in ~30 minutes of focused agent work.
4. Update state.json: `plan.status = "complete"`, `plan.asset = ".claude/features/<TICKET>/tasks.md"`, `implement.tasks_total = <count>`.

### Stage 3 — implement (`implement`)

For each task in `tasks.md`:

1. Create or check out the feature branch: `feat/<TICKET-lowercase>-<short-slug>`. Persist to `state.json:branch`.
2. Spawn a subagent with the `agent-skills:incremental-implementation` skill (or `:build`). Hand it:
   - Path to `brief.md`
   - The single task's section from `tasks.md` (extract by heading)
   - A directive: after the task is done, run `bash scripts/verify.sh` (the project's verify entrypoint — see the `verify-architecture` skill for the contract) and only commit if it passes.
3. If the consuming project has wired a PostEdit hook to `scripts/verify.sh --quick`, the hook auto-runs after every Edit/Write. The subagent must not bypass failures regardless.
4. On success, increment `implement.tasks_completed`. Write state.json.
5. If a task fails repeatedly (3 attempts), mark `implement.status = "failed"` and surface to the human.

### Stage 4 — open PR (`pr`)

1. Push the branch.
2. Open the PR via `gh pr create`. Title format: `<TICKET>: <brief title>`. Body must include:
   - Link to the tracker ticket
   - Embedded link to the brief
   - Summary (2–4 bullets, pulled from brief)
   - Test plan checklist (pulled from acceptance criteria)
3. Capture the PR URL + number in `state.json:pr`.

### Stage 5 — review loop (`review_loop`)

Loop, increment `round` per iteration. While `round < max_rounds`:

1. Invoke `pr-review-orchestrator` skill. It spawns the 4-agent review team in parallel and returns when all comments are posted.
2. Invoke `pr-triage` skill. It triages each comment, replies, creates tracker subtasks for "later", and returns `{ will_fix: [...], wont_fix: [...], later: [...] }`.
3. Append the round summary to `review_loop.rounds`.
4. If `will_fix` is empty → exit loop.
5. Else: spawn an implementation subagent with the will-fix list and `brief.md`. It fixes and pushes. Loop.

On loop exit:

- If still has `will_fix` after `max_rounds` reached → mark `review_loop.status = "needs_human"`.
- Otherwise → `review_loop.status = "complete"`.

### ⏸ Human checkpoint 2

Notify the human (text output to the user) with the PR URL, round count, and the lists of won't-fix + later items so they have full context for final review. Ask: _Merge_, _Iterate_, _Abandon_.

## Behaviors

- **Idempotent**: re-running the conductor reads state.json and resumes from the current stage. Never redo a `complete` stage.
- **Token discipline**: never re-read source-of-truth artifacts that a prior stage already consumed. The brief is the canonical contract from Stage 2 onward.
- **Failure transparency**: any stage failure pauses the loop and surfaces the error to the human verbatim. Don't paper over.
- **No silent destructive ops**: branch deletion, force-push, rebase, etc. require human confirmation regardless of round.

## Output

After every stage, emit a single concise update to the user: `Stage N: <status>. Next: <action or checkpoint>.` Nothing else.
