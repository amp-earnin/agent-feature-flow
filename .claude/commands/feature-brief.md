---
description: Run only the brief (gather + author) stage of the feature workflow. Stops at human checkpoint 1.
argument-hint: <TICKET-ID> [--continue]  e.g. ABC-1234
---

You are running **stage 1 (brief)** of the agentic feature workflow for ticket: **$ARGUMENTS**

## Your job

1. **Parse arguments**: the first token is the ticket ID (default regex `^[A-Z]+-\d+$`); the optional flag `--continue` switches mode from `only` (default) to `continue` (run brief + all downstream stages). If the ticket ID is missing or malformed, ask the user and stop.

2. **Set up workspace**: ensure `.claude/features/<TICKET>/` exists. If `state.json` already exists, this is a re-run of the brief stage — proceed (the conductor will overwrite).

3. **Invoke the conductor** with `TICKET=<ticket>`, `start_stage=brief`, and `mode=only` (or `continue` if the flag was passed).

4. **Surface human checkpoint 1**: when the conductor returns at the brief checkpoint, use `AskUserQuestion` with options _Approved_ / _Needs revisions_ / _Cancel_. In `only` mode, stop after the human responds — do not advance to plan.

## Constraints

- Do not implement code in this turn.
- Do not read brief contents yourself — the conductor delegates to a subagent.
- If the user passed `--continue`, behave like `/feature` from this point onward.
