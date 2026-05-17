---
description: Run only the review-loop stage (parallel reviewers + triage, up to 5 rounds). Stops at human checkpoint 2.
argument-hint: <TICKET-ID>  e.g. ABC-1234
---

You are running **stage 5 (review loop)** of the agentic feature workflow for ticket: **$ARGUMENTS**

## Your job

1. **Parse arguments**: first token is the ticket ID. Validate it; if malformed, ask and stop. (`--continue` has no effect here — review loop is the final automated stage; checkpoint 2 is always surfaced.)

2. **Verify prerequisite**: confirm an open PR exists for this ticket — either `state.json:pr.url` is populated, or `gh pr view` on the current branch returns an open PR. If not, stop and tell the user:

   > No open PR found for `<TICKET>`. Run `/feature-pr <TICKET>` first.

3. **Invoke the conductor** with `TICKET=<ticket>`, `start_stage=review_loop`, and `mode=only`. The conductor seeds upstream stages as complete, runs the parallel-reviewer loop, and pauses at checkpoint 2.

4. **Surface human checkpoint 2**: when the conductor returns, use `AskUserQuestion` with options _Merge_ / _Iterate_ / _Abandon_. Pass the PR URL, round count, and won't-fix + later lists in the question context.

## Constraints

- Do not review code yourself — the 4-agent reviewer team runs in parallel subagents.
- Do not merge the PR — that is the human's decision at checkpoint 2.
