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

4. **Surface human checkpoint 2**: when the conductor returns, use `AskUserQuestion`. The options depend on the loop outcome:
   - Loop converged clean (`review_loop.status === "complete"`): _Merge_ / _Iterate_ / _Abandon_.
   - Loop exited because we don't own the branch (`review_loop.status === "needs_human"`, fork PR): _Approve_ / _Request changes (relay punch list)_ / _Abandon_. "Iterate" is not offered because we cannot push fixes.
   - Loop hit `max_rounds` with unresolved will-fix: same as the fork case — surface the remaining will-fix as a punch list.

   Pass the PR URL, round count, and won't-fix + later lists in the question context.

## Constraints

- Do not review code yourself — the 4-agent reviewer team runs in parallel subagents.
- Do not merge the PR — that is the human's decision at checkpoint 2.
- In PR mode, do not invent a ticket ID and do not silently switch modes based on PR title content.
