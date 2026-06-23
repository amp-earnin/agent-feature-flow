---
description: Run only the plan (task breakdown) stage of the feature workflow. Requires brief.md to exist.
argument-hint: <TICKET-ID> [--continue]  e.g. ABC-1234
---

You are running **stage 2 (plan)** of the agentic feature workflow for ticket: **$ARGUMENTS**

## Your job

1. **Parse arguments**: first token is the ticket ID; optional `--continue` flag switches mode from `only` (default) to `continue`. Validate the ticket ID against the default regex `^[A-Z]+-\d+$`; if malformed, ask and stop.

2. **Verify prerequisite**: confirm `.claude/features/<TICKET>/brief.md` exists. If not, stop and tell the user:

   > No `brief.md` found for `<TICKET>`. Either run `/feature-brief <TICKET>` to author one, or write `.claude/features/<TICKET>/brief.md` yourself and re-run this command.

3. **Call the `feature-flow-conductor` skill** (via the **Skill tool**) with `TICKET=<ticket>`, `start_stage=plan`, and `mode=only` (or `continue` if the flag was passed). The conductor will seed `state.json` (marking brief complete) before it dispatches the plan subagent.

4. **Report result**: emit `Stage 2 complete. Next: /feature-implement <TICKET> or pass --continue to chain.` in `only` mode.

## Constraints

- Do not write tasks yourself — the conductor delegates to the planning subagent.
- Do not modify `brief.md` — it is the canonical contract from this stage onward.
