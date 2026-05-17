---
description: Run only the PR-open stage. Pushes the current feature branch and opens a PR.
argument-hint: <TICKET-ID> [--continue]  e.g. ABC-1234
---

You are running **stage 4 (open PR)** of the agentic feature workflow for ticket: **$ARGUMENTS**

## Your job

1. **Parse arguments**: first token is the ticket ID; optional `--continue` flag switches mode from `only` (default) to `continue` (run PR + review loop). Validate the ticket ID; if malformed, ask and stop.

2. **Verify prerequisite**: confirm a feature branch with commits ahead of the base branch is checked out (or recorded in `state.json:branch`). If no branch is found, stop and tell the user:

   > No feature branch with commits found for `<TICKET>`. Run `/feature-implement <TICKET>` first or check out the branch manually.

3. **Invoke the conductor** with `TICKET=<ticket>`, `start_stage=pr`, and `mode=only` (or `continue` if the flag was passed). The conductor seeds upstream stages as complete and dispatches the PR-open subagent.

4. **Report result**: surface the PR URL to the user. In `only` mode, suggest `/feature-review <TICKET>` as the next step.

## Constraints

- Do not push or open the PR yourself — the conductor handles all `git` and `gh` operations.
- Do not amend or force-push existing commits.
