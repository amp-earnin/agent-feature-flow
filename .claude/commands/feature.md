---
description: Run the end-to-end agentic feature workflow for a tracker ticket (gather → plan → implement → PR → review-loop → human merge).
argument-hint: <TICKET-ID>  e.g. ABC-1234
---

You are starting the agentic feature workflow for ticket: **$ARGUMENTS**

## What this command does

It runs a 6-stage workflow with 2 human checkpoints:

```
gather requirements → ⏸ HUMAN: approve brief
                    → plan
                    → implement (per-task, verify.sh gates each commit)
                    → open PR
                    → review loop (4 parallel reviewers + triage, up to 5 rounds)
                    → ⏸ HUMAN: merge or iterate
```

## Your job in this turn

1. **Validate input**: confirm `$ARGUMENTS` looks like a tracker ticket ID. The default regex is `^[A-Z]+-\d+$` (JIRA-style — e.g. `ABC-1234`, `PROJ-42`); if your tracker uses a different shape, edit this command in your project's `.claude/commands/feature.md` to match. If `$ARGUMENTS` doesn't match, ask the user to provide one and stop.

2. **Set up workspace**: ensure `.claude/features/$ARGUMENTS/` exists. If `state.json` already exists, this is a **resume** — read it and report the current stage to the user before proceeding. If it doesn't exist, this is a **fresh run** — create state.json with the schema from `feature-flow-conductor`.

3. **Invoke the conductor**: call the `feature-flow-conductor` skill with the ticket ID. The conductor drives all 6 stages and surfaces the two human checkpoints back to you.

4. **Surface checkpoints to the user**: when the conductor pauses for a human checkpoint, use the `AskUserQuestion` tool with appropriate options (Approve / Revise / Cancel for the brief; Merge / Iterate / Abandon at the end).

## Constraints

- Do **not** implement code in this turn. You are the kickoff layer.
- Do **not** read the brief, plan, or source files yourself — the conductor delegates each stage to a subagent with fresh context, which is the point.
- Do **not** create branches, commits, or PRs directly — the conductor handles all git/gh operations.
- If `$ARGUMENTS` is empty, ask the user for the ticket ID and stop.

## On failure

If any stage reports `status: failed`, the conductor will return control to you with an error. Surface that verbatim to the user with no rewriting — and propose either "retry the failed stage" or "drop me into manual mode for this stage" as next steps.
