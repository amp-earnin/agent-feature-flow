---
description: Run the parallel reviewer loop on an open PR (by ticket ID or bare PR number; PR mode is review-only).
argument-hint: <TICKET-ID | PR-NUMBER>  e.g. ABC-1234 or #123
---

You are running **stage 5 (review loop)** of the agentic feature workflow.

Argument: **$ARGUMENTS**

## Your job

1. **Parse the argument** — trim leading/trailing whitespace from `$ARGUMENTS` first, then detect mode:
   - **Ticket mode**: matches `^[A-Z][A-Z0-9]+-\d+$` (e.g. `ABC-1234`). Use the existing feature workspace at `.claude/features/<TICKET>/`.
   - **PR mode**: matches `^#\d+$` (e.g. `#123`). Strip the `#`. There is no ticket and no brief — review the PR on its own merits. **The leading `#` is required** to disambiguate from purely-numeric tracker conventions (Linear, Shortcut). A bare `123` falls through to the clarify branch.
   - Anything else: stop and post the following message verbatim to the user, then exit:

     > `<ARG>` is not a recognized ticket ID or PR number. Expected a tracker ID like `ABC-1234`, or a PR number prefixed with `#` like `#123`.

2. **Verify prerequisite**:
   - Ticket mode: confirm an open PR exists for this ticket — either `state.json:pr.url` is populated, or `gh pr view` on the current branch returns an open PR. If not, stop and tell the user:

     > No open PR found for `<TICKET>`. Run `/feature-pr <TICKET>` first.

   - PR mode: run `gh pr view <PR_NUMBER> --json number,url,headRefName,headRepositoryOwner,title,body,state`. If the PR is not found or not open, stop with:

     > PR #`<N>` is not available (state: `<state or "not found">`). Aborting.

3. **Invoke the conductor** with `start_stage=review_loop`, `mode=only`, and either:
   - Ticket mode: `TICKET=<ticket>` — the conductor seeds upstream stages as complete using the existing brief and PR.
   - PR mode: `PR=<number>` (no TICKET). The conductor handles workspace seeding, PR-context persistence, branch-ownership detection, and the review loop.

   The conductor runs the convergence loop: reviewers → triage → if will-fix is empty exit clean, else apply fixes and re-review, up to `max_rounds` (default 5). The auto-fix-and-re-review step is gated on whether we own the head branch — if the PR is from a fork or otherwise un-pushable, the loop exits after one round with the will-fix list surfaced to the human as a punch list.

4. **Surface human checkpoint 2**: when the conductor returns, dispatch on `review_loop.exit_reason`:
   - `"clean"`: loop converged. Options: _Merge_ / _Iterate_ / _Abandon_.
   - `"max_rounds_exhausted"` AND `pr.owns_branch === true` (ticket mode, or PR-only mode on an in-repo branch): options remain _Merge_ / _Iterate_ / _Abandon_ — the human can choose to drive another round manually if they think the remaining will-fix items are addressable. Surface the remaining `will_fix` as a punch list in the question context so the human has full information.
   - `"unpushable"` (fork PR or no-push-rights): options _Approve_ / _Request changes (relay punch list)_ / _Abandon_. _Iterate_ is **not** offered because we cannot push fixes — the PR author must do that, on their fork.

   Always pass the PR URL, round count, won't-fix list, and later list in the question context.

## Direct callers

If you're invoking `pr-review-orchestrator` or `pr-triage` directly (outside this command), pass one of these two call shapes:

- **Ticket mode**: pass `WORKSPACE=<TICKET-ID>` AND `TICKET=<TICKET-ID>` (same value — the ticket-mode invariant requires `WORKSPACE === TICKET`).
- **PR-only mode**: pass `WORKSPACE=_pr-<number>` and omit `TICKET`.

The conductor performs this mapping for you when you go through `/feature-review`, so the slash command's contract here (step 3) is unchanged.

## Constraints

- Do not review code yourself — the 4-agent reviewer team runs in parallel subagents.
- Do not merge the PR — that is the human's decision at checkpoint 2.
- In PR mode, do not invent a ticket ID and do not silently switch modes based on PR title content.
