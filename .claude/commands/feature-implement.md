---
description: Run only the implement stage (task-by-task build with verify gates). Requires brief.md and tasks.md.
argument-hint: <TICKET-ID> [--continue]  e.g. ABC-1234
---

You are running **stage 3 (implement)** of the agentic feature workflow for ticket: **$ARGUMENTS**

## Your job

1. **Parse arguments**: first token is the ticket ID; optional `--continue` flag switches mode from `only` (default) to `continue`. Validate the ticket ID; if malformed, ask and stop.

2. **Verify prerequisites**: confirm both files exist:
   - `.claude/features/<TICKET>/brief.md`
   - `.claude/features/<TICKET>/tasks.md`

   If either is missing, stop and tell the user which file is missing and that they should run the upstream stage (`/feature-brief` or `/feature-plan`) or write the file themselves.

3. **Call the `feature-flow-conductor` skill** (via the **Skill tool**) with `TICKET=<ticket>`, `start_stage=implement`, and `mode=only` (or `continue` if the flag was passed). The conductor seeds `state.json` (brief + plan marked complete) before it dispatches the per-task subagents.

4. **Report result**: emit a one-line summary of tasks completed and the branch name. In `only` mode, suggest `/feature-pr <TICKET>` as the next step.

## Constraints

- Do not implement tasks yourself — every task runs in a fresh-context subagent.
- Do not bypass `scripts/verify.sh` failures.
- Do not modify `brief.md` or `tasks.md`.
