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
   - PR mode: `PR=<number>` (no TICKET). The conductor handles workspace seeding, PR-context persistence, and the review-and-triage loop. **PR mode is review-only** — the conductor will not spawn implementation subagents to apply will-fixes, since the head branch may belong to an external contributor on a fork. Will-fixes are surfaced to the human at checkpoint 2 as a punch list.

4. **Surface human checkpoint 2**: when the conductor returns, use `AskUserQuestion`. In ticket mode the options are _Merge_ / _Iterate_ / _Abandon_. In PR mode the options are _Approve_ / _Request changes_ / _Abandon_ (no Iterate — see above). Pass the PR URL, round count, and won't-fix + later lists in the question context.

## Constraints

- Do not review code yourself — the 4-agent reviewer team runs in parallel subagents.
- Do not merge the PR — that is the human's decision at checkpoint 2.
- In PR mode, do not invent a ticket ID and do not silently switch modes based on PR title content.
