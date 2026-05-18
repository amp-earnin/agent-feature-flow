---
description: Run only the review-loop stage (parallel reviewers + triage, up to 5 rounds). Accepts a ticket ID or a PR number.
argument-hint: <TICKET-ID | PR-NUMBER>  e.g. ABC-1234 or 123
---

You are running **stage 5 (review loop)** of the agentic feature workflow.

Argument: **$ARGUMENTS**

## Your job

1. **Parse the argument** — detect which mode you're in:
   - **Ticket mode**: matches `^[A-Z][A-Z0-9]+-\d+$` (e.g. `ABC-1234`). Use the existing feature workspace at `.claude/features/<TICKET>/`.
   - **PR mode**: matches `^#?\d+$` (e.g. `123` or `#123`). Strip the `#`. There is no ticket and no brief — review the PR on its own merits.
   - Anything else: ask the user to clarify and stop.

2. **Verify prerequisite**:
   - Ticket mode: confirm an open PR exists for this ticket — either `state.json:pr.url` is populated, or `gh pr view` on the current branch returns an open PR. If not, stop and tell the user:

     > No open PR found for `<TICKET>`. Run `/feature-pr <TICKET>` first.

   - PR mode: run `gh pr view <PR_NUMBER> --json number,url,headRefName,title,body,state`. If the PR is not found or not open, stop and tell the user.

3. **Invoke the conductor** with `start_stage=review_loop`, `mode=only`, and either:
   - Ticket mode: `TICKET=<ticket>` — the conductor seeds upstream stages as complete using the existing brief and PR.
   - PR mode: `PR=<number>` (no TICKET). The conductor must:
     1. Use workspace `.claude/features/pr-<number>/` (create if missing).
     2. Seed a minimal `state.json` with `ticket: null`, `pr.number`, `pr.url`, all upstream stages marked `complete` with `asset: null`, and `review_loop.status = "in_progress"`.
     3. Run the parallel-reviewer loop. Downstream skills (`pr-review-orchestrator`, `pr-triage`) must tolerate a null ticket and a missing `brief.md` — reviewers fall back to PR title + body as context, and triage skips the tracker-subtask creation for `later` items (instead reply with `[later] Out of scope for this review; track separately.`).

4. **Surface human checkpoint 2**: when the conductor returns, use `AskUserQuestion` with options _Merge_ / _Iterate_ / _Abandon_. Pass the PR URL, round count, and won't-fix + later lists in the question context.

## Constraints

- Do not review code yourself — the 4-agent reviewer team runs in parallel subagents.
- Do not merge the PR — that is the human's decision at checkpoint 2.
- In PR mode, do not invent a ticket ID. If the PR title contains a recognizable ticket pattern, you MAY surface it to the user and offer to re-run in ticket mode, but do not silently switch modes.
