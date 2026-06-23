---
description: Run the parallel reviewer loop on an open PR (by ticket ID or bare PR number; PR mode is review-only). Add `--stacked` for non-invasive PR review delivered as a separate PR. Add `--interactive` (stacked-only, with a Slack thread permalink) to layer Slack coordination and a comment-driven fix loop on the delivery PR.
argument-hint: <TICKET-ID | PR-NUMBER> [--stacked] [--interactive <slack-thread-url> [--poll <min>] [--idle <min>]]  e.g. ABC-1234 or #123 or #123 --stacked or #123 --stacked --interactive https://your.slack.com/archives/C.../p...
---

You are running **stage 5 (review loop)** of the agentic feature workflow.

Argument: **$ARGUMENTS**

## Your job

1. **Parse the arguments** — trim leading/trailing whitespace from `$ARGUMENTS` first, then split on whitespace into tokens. Token order does not matter throughout this step. Pull the following out of the token list (each is order-independent — `#123 --stacked` and `--stacked #123` are equivalent):
   - **`--stacked`** — boolean flag.
   - **`--interactive`** — boolean flag. Opt-in; layers Slack coordination and a comment-driven fix loop onto a stacked review.
   - **`--poll <int>`** and **`--idle <int>`** — optional integer flags (each consumes the next token as its value). Cadence overrides forwarded as raw integers; the conductor resolves them against its `5` / `30` defaults.

   After removing those flags (and the values consumed by `--poll` / `--idle`), classify the remaining tokens **by presence, not format**:
   - The **ticket/PR target** is the token matching a ticket ID (`^[A-Z][A-Z0-9]+-\d+$`) or a PR number (`^#\d+$`).
   - Any other remaining non-flag token is the **raw Slack-target string** (a Slack thread permalink). It is recognized purely by presence — **do not** validate its format, **do not** parse it into a channel ID / thread ts, and **do not** probe for a connector. The command only selects the mode and forwards this string verbatim; permalink format validation, channel/ts extraction, and the connector probe all happen later in the conductor, and a malformed or unreachable permalink is established as invalid at access time there, not rejected here.

   Detect mode from the target token:
   - **Ticket mode**: matches `^[A-Z][A-Z0-9]+-\d+$` (e.g. `ABC-1234`). Use the existing feature workspace at `.claude/features/<TICKET>/`.
   - **PR mode**: matches `^#\d+$` (e.g. `#123`). Strip the `#`. There is no ticket and no brief — review the PR on its own merits. **The leading `#` is required** to disambiguate from purely-numeric tracker conventions (Linear, Shortcut). A bare `123` falls through to the clarify branch.
   - Anything else (no target token, an unrecognized target, or more than one non-flag token left **after** setting aside the recognized Slack-target string — i.e. a stray token that is neither the target nor the single allowed Slack permalink): stop and post the following message verbatim to the user, then exit:

     > `<ARG>` is not a recognized ticket ID or PR number. Expected a tracker ID like `ABC-1234`, or a PR number prefixed with `#` like `#123`.

   **`--stacked` is PR-mode only.** Stacked mode reviews someone else's open PR non-invasively, so it has no ticket. If `--stacked` is present in **ticket mode**, stop and post the following message verbatim to the user, then exit:

   > `--stacked` reviews an open PR non-invasively and delivers fixes as a separate PR, so it needs a PR number — not a ticket. Re-run as `/feature-review #<PR> --stacked`.

   **`--interactive` syntactic gates (flag-combo validity only — NOT permalink format).** These run only when `--interactive` is present; plain `--stacked` (no `--interactive`) and every other invocation are unaffected. The checks are order-independent and are purely syntactic — the command never validates the permalink's format, never parses it into a channel ID / thread ts, and never probes for a connector. A malformed or unreachable permalink is **not** rejected here; target validity is established at access time in the conductor (the connector probe / first post), which fails with a clear runtime error if the channel/thread cannot be reached. Apply both gates:

   - **(a)** If `--interactive` is present but `--stacked` is **not** present, OR the target is a ticket (ticket mode), stop and post the following message verbatim to the user, then exit:

     > `--interactive requires --stacked and a bare PR number. Interactive review is only available for stacked PR review; it cannot run against a ticket target.`

   - **(b)** If `--interactive` (or `--stacked`) is present but **no** Slack-thread argument was supplied (presence check only — this fires solely for a _missing_ argument, never for a malformed/unparseable permalink), stop and post the following message verbatim to the user, then exit:

     > `--interactive requires a Slack thread permalink (e.g. https://your.slack.com/archives/C…/p…). None was supplied.`

2. **Verify prerequisite**:
   - Ticket mode: confirm an open PR exists for this ticket — either `state.json:pr.url` is populated, or `gh pr view` on the current branch returns an open PR. If not, stop and tell the user:

     > No open PR found for `<TICKET>`. Run `/feature-pr <TICKET>` first.

   - PR mode: run `gh pr view <PR_NUMBER> --json number,url,headRefName,headRepositoryOwner,title,body,state`. If the PR is not found or not open, stop with:

     > PR #`<N>` is not available (state: `<state or "not found">`). Aborting.

3. **Call the `feature-flow-conductor` skill** (via the **Skill tool**) with `start_stage=review_loop`, `mode=only`, and either:
   - Ticket mode: `TICKET=<ticket>` — the conductor seeds upstream stages as complete using the existing brief and PR. `review_mode=in_place` (the default; ticket runs are always in-place).
   - PR mode: `PR=<number>` (no TICKET). The conductor handles workspace seeding, PR-context persistence, branch-ownership detection, and the review loop. Pass `review_mode=stacked` when the `--stacked` flag was parsed in step 1; otherwise `review_mode=in_place` (the default).

   When `--interactive` was parsed in step 1 (PR mode, having passed the gates above), additionally forward the interactive inputs as **raw values** — the command does not transform them:
   - `interactive=true`.
   - the raw Slack-target string, exactly as supplied (the conductor extracts the channel ID / thread ts and proves reachability by access — see its Slack-target parsing and connector-probe steps).
   - `poll=<int>` and/or `idle=<int>` when those flags were supplied, as raw integers (the conductor resolves them against its `5` / `30` defaults and persists the result).

   The command forwards these and stops there: it implements no loop behavior, no permalink parsing, and no connector probe — those belong to the conductor.

   The conductor runs the convergence loop: reviewers → triage → if will-fix is empty exit clean, else apply fixes and re-review, up to `max_rounds` (default 5). The auto-fix-and-re-review step is gated on whether we own the head branch — if the PR is from a fork or otherwise un-pushable, the loop exits after one round with the will-fix list surfaced to the human as a punch list.

   In `review_mode=stacked` the loop runs at full fidelity but **never mutates the target PR** (no comments, no commits to its head): the reviewer↔triage↔fixer loop coordinates entirely in the workspace, and the agreed fixes are delivered as a separate, reviewable PR. The conductor owns all of that behavior — this command only selects the mode.

4. **Surface human checkpoint 2**: when the conductor returns, branch on `review_loop.exit_reason`:

   **In-place exit reasons** (`review_mode=in_place` — unchanged):
   - `"clean"`: loop converged. Options: _Merge_ / _Iterate_ / _Abandon_.
   - `"max_rounds_exhausted"` AND `pr.owns_branch === true` (ticket mode, or PR-only mode on an in-repo branch): options remain _Merge_ / _Iterate_ / _Abandon_ — the human can choose to drive another round manually if they think the remaining will-fix items are addressable. Surface the remaining `will_fix` as a punch list in the question context so the human has full information.
   - `"unpushable"` (fork PR or no-push-rights): options _Approve_ / _Request changes (relay punch list)_ / _Abandon_. _Iterate_ is **not** offered because we cannot push fixes — the PR author must do that, on their fork.

   For the in-place reasons, always pass the PR URL, round count, won't-fix list, and later list in the question context.

   **Stacked exit reason** (`review_mode=stacked`):
   - `"delivered"`: the loop finished and the separate delivery PR was opened — the target PR was never mutated. **Never offer _Merge_** (we never merge the target). Options: _Done (delivery PR open)_ / _Iterate (drive another round on the **delivery** branch)_ / _Abandon (close the delivery PR)_. Always surface in the question context: the **delivery PR URL** (`review_loop.delivery.pr_url`), the **target PR URL** (`stages.pr.url`), the **round count**, the **won't-fix and later lists**, and the **capped status** (`review_loop.delivery.capped` — `true` means the round cap was hit and the delivery PR carries an unresolved must-fix punch list). The cap is conveyed by `delivery.capped`, not by a separate exit reason.

## Direct callers

If you're invoking `pr-review-orchestrator` or `pr-triage` directly (outside this command), pass one of these two call shapes:

- **Ticket mode**: pass `WORKSPACE=<TICKET-ID>` AND `TICKET=<TICKET-ID>` (same value — the ticket-mode invariant requires `WORKSPACE === TICKET`).
- **PR-only mode**: pass `WORKSPACE=_pr-<number>` and omit `TICKET`. For stacked review, additionally pass `review_mode=stacked`; otherwise it defaults to `review_mode=in_place`. Stacked mode is always PR-only-shaped — never combine it with a `TICKET`.

The conductor performs this mapping for you when you go through `/feature-review`, so the slash command's contract here (step 3) is unchanged.

## Constraints

- Do not review code yourself — the 4-agent reviewer team runs in parallel subagents.
- Do not merge the PR — that is the human's decision at checkpoint 2.
- In PR mode, do not invent a ticket ID and do not silently switch modes based on PR title content.
- `--stacked` is PR-mode only. Never accept it alongside a ticket ID — stop with the verbatim error in step 1 — and never synthesize a ticket to make it fit.
- Do not implement stacked behavior in this command. It only parses `--stacked` and forwards `review_mode=stacked`; the conductor enforces the no-target-PR-mutation invariant and the separate delivery PR.
