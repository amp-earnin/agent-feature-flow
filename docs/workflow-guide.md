# Agentic feature workflow — usage guide

This guide is for humans driving the `/feature` workflow. It explains what the workflow does, where to step in, and how to recover when things go sideways.

## TL;DR

```
/feature ABC-1234
```

The workflow runs 6 stages and pauses twice for your approval:

1. **Gather requirements** → 2. **Plan tasks** → 3. **Implement** → 4. **Open PR** → 5. **Review loop** → 6. **Merge**

Two human checkpoints: after the **brief** is generated (Stage 1), and before **merge** (Stage 6).

## What each stage produces

| Stage                    | Output                         | Location                             |
| ------------------------ | ------------------------------ | ------------------------------------ |
| 1. Gather + author brief | `brief.md` (+ tracker comment) | `.claude/features/<TICKET>/brief.md` |
| 2. Plan                  | `tasks.md` (ordered, sized)    | `.claude/features/<TICKET>/tasks.md` |
| 3. Implement             | branch + commits               | git branch `feat/<ticket>-<slug>`    |
| 4. Open PR               | PR URL                         | GitHub                               |
| 5. Review loop           | PR comments + triage replies   | GitHub PR                            |
| 6. Merge                 | merged commit                  | your main branch                     |

State is persisted to `.claude/features/<TICKET>/state.json` (schema: `${CLAUDE_PLUGIN_ROOT}/references/state-schema.json`) so the workflow can be paused at any point and resumed by re-running `/feature <TICKET>`.

## Running a single stage

Sometimes you don't want the full pipeline. Maybe you wrote the brief yourself and just want planning to run, or maybe Stage 3 finished a week ago and you only want to re-open the PR. Each stage has its own slash command:

| Command                                                            | Enters at      | Default behavior                                                                                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------ | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/feature-brief <TICKET>`                                          | gather + brief | runs Stage 1, stops at human checkpoint 1                                                                                                                                                                                                                                                                                                                                     |
| `/feature-plan <TICKET>`                                           | plan           | runs Stage 2 only — requires `brief.md`                                                                                                                                                                                                                                                                                                                                       |
| `/feature-implement <TICKET>`                                      | implement      | runs Stage 3 only — requires `brief.md` + `tasks.md`                                                                                                                                                                                                                                                                                                                          |
| `/feature-pr <TICKET>`                                             | open PR        | runs Stage 4 only — requires a feature branch with commits                                                                                                                                                                                                                                                                                                                    |
| `/feature-review <TICKET>`                                         | review loop    | runs Stage 5 + checkpoint 2 — requires an open PR for this ticket                                                                                                                                                                                                                                                                                                             |
| `/feature-review #<PR>`                                            | review loop    | PR-only mode — review any open PR by number; no ticket / brief required; auto-fix loop runs if `gh pr checkout` succeeds (i.e. the head branch is in this repo and we have push rights), otherwise emits a punch list                                                                                                                                                         |
| `/feature-review #<PR> --stacked`                                  | review loop    | Non-invasive PR-only mode — runs the full review-fix loop without ever touching the target PR (no comments, no commits) and delivers the agreed fixes as a separate, reviewable PR with the original author looped in as reviewer. See [Stacked-pr review mode](#stacked-pr-review-mode)                                                                                      |
| `/feature-review #<PR> --stacked --interactive <slack-thread-url>` | review loop    | Adds Slack coordination and a comment-driven fix loop to a stacked review. Announces the review in a Slack thread, then monitors the **delivery** PR — turning each new human comment into a multiple-choice reply and applying the chosen fix. Opt-in; only valid with `--stacked` + a Slack thread permalink. See [Interactive stacked review](#interactive-stacked-review) |

**Default is "only this stage."** Pass `--continue` to run that stage and everything downstream:

```bash
/feature-plan ABC-1234            # plan, then stop
/feature-plan ABC-1234 --continue # plan + implement + PR + review, like /feature did from this point
```

If a prerequisite is missing the command **fails with instructions** — it does not auto-run upstream stages. You can supply the missing artifact two ways:

- run the upstream command (`/feature-brief`, `/feature-plan`, etc.), or
- write the file yourself at `.claude/features/<TICKET>/<file>.md` and re-run

The conductor seeds `state.json` based on which artifacts it finds on disk, so writing a brief by hand and jumping to `/feature-plan` works the same as running both commands in sequence.

## Prerequisites

Before your first run, complete the steps in `${CLAUDE_PLUGIN_ROOT}/references/consumer-setup-checklist.md`. Most importantly:

1. The tracker MCP server (Atlassian Rovo for JIRA, or equivalent) is authenticated.
2. `scripts/verify.sh` exists in your project and passes on `main` / `develop`.
3. The two reviewer agents have project-scoped overrides at `.claude/agents/{architecture-reviewer,frontend-ux-reviewer}.md`.

## The two checkpoints

### Checkpoint 1 — after the brief

You'll see a prompt with three options:

- **Approved** — proceed to planning.
- **Needs revisions** — provide notes; the gather stage re-runs incorporating them.
- **Cancel** — abandon the workflow. State is preserved; you can resume later.

**What to look for in the brief**:

- Acceptance criteria match what the ticket actually asks for.
- "Out of scope" is accurate — no creep.
- "Open questions" — ambiguities flagged. If there are unresolved ambiguities critical to implementation, resolve them with the ticket author **before** approving. The brief is canonical; downstream agents won't re-read the tracker.

### Checkpoint 2 — before merge

You'll see a summary:

- PR URL
- Rounds of review run (1–5 by default)
- Won't-fix decisions made by triage (with reasoning)
- "Later" subtasks created in your tracker

Options:

- **Merge** — merge per repo convention.
- **Iterate** — you have changes to request; provide notes, the workflow re-enters the review loop.
- **Abandon** — close the PR (you'll be asked to confirm).

**What to look for at the final checkpoint**:

- Won't-fix items — are any actually blocking?
- Later subtasks — are any actually in-scope for this PR?
- The diff itself — read it. Triage is automatic but not infallible.

## Token-optimization design (why the workflow looks like this)

Each stage runs in a **fresh-context subagent** that reads only the previous stage's output. The brief is the canonical contract. Implementation agents never re-read the tracker / Figma / Slack — they read `brief.md`. This is intentional:

- Reduces context bloat → fewer hallucinations.
- Makes stage outputs human-auditable.
- Lets you fix a wrong implementation by fixing `brief.md` and re-running from Stage 2.

## Executable verification

If you've wired the PostEdit hook (step 3 in the setup checklist), every Edit / Write triggers `scripts/verify.sh --quick` on the changed file (typically lint + format). At the end of every task, the implementation agent runs the full `scripts/verify.sh` (typecheck, lint, format, unit tests, and any custom architecture rules).

Code does not get committed if `verify.sh` fails. See [architecture-rules.md](./architecture-rules.md) for how custom rules work and the examples that ship with this plugin.

To run verification yourself:

```bash
bash scripts/verify.sh                            # full suite
bash scripts/verify.sh --quick --file <path>      # just one file (lint + format)
```

## The review loop

Stage 5 spawns 4 reviewers in parallel:

| Reviewer     | Lane                                | Subagent                                                   |
| ------------ | ----------------------------------- | ---------------------------------------------------------- |
| Correctness  | bugs, missed cases                  | `agent-skills:code-reviewer` (default)                     |
| Architecture | structure, patterns                 | `architecture-reviewer` (this plugin; consumer-overridden) |
| Security     | OWASP, secrets, auth                | `agent-skills:security-auditor` (default)                  |
| Frontend/UX  | data fetching, forms, a11y, styling | `frontend-ux-reviewer` (this plugin; consumer-overridden)  |

Each posts comments tagged with their lane (`[correctness]`, `[arch]`, `[security]`, `[ux]`), one issue per comment. See `${CLAUDE_PLUGIN_ROOT}/references/lane-tags.md` for the tag contract.

Then a triage subagent classifies each comment as **will-fix / won't-fix / later**, replies on the thread, creates tracker subtasks for "later," and hands the will-fix list to an implementation subagent.

The implementation subagent applies fixes, runs `verify.sh`, commits, pushes, and **resolves the GitHub review thread** for each will-fix item. The next round's reviewers begin with **Step A — re-review of prior fixes**: for each resolved thread in their lane, they re-read the file at the original `path:line` against the new HEAD and either leave the thread resolved (the fix landed) or **unresolve it** and post `[<lane>] Fix from round N not landed (re-review at round N+1): ...`. That reply enters the same round's triage as a normal finding and flows through the same will-fix path. Watching the PR conversation, you'll see threads tick to resolved as the loop converges; any that get re-opened across rounds point exactly to fixes the reviewers rejected.

Loop continues until `will-fix` is empty (and no Step-A thread was rejected) or `max_rounds` (default 5) is reached. Configure max rounds by editing `state.json:review_loop.max_rounds` before the loop starts.

**Reviewer quality bar — ground regression claims in source/docs.** Before any reviewer asserts (in a first-pass review or a Step-A re-review) that a change is a _regression_ or a _bug_, it must verify the claim against the installed library source or the official docs — not reason about the diff in a vacuum. If it can't ground the claim, it downgrades the finding to a question or drops it. This closes a known false-positive class where a reviewer "discovers" a regression by reasoning about agent-written code without checking that the framework already handles the case. The bar applies in every mode; it matters most in stacked mode, where the only externally-visible output is the delivery PR body, so an unverified claim would ship unchallenged.

### Stacked-pr review mode

`/feature-review #<PR> --stacked` reviews someone else's open PR **non-invasively**. It runs the same Stage 5 loop — same four lanes, same triage classification, same `scripts/verify.sh` gate before any fix is accepted, same re-review/convergence behavior and same round cap — but it never touches the target PR and delivers the agreed fixes as a separate PR. It is **not a new workflow stage**: the workflow is still the same 6 stages, and stacked mode is a parameter of the existing review loop (`review_loop.review_mode = "stacked"`). It adds **no new required dependencies** — it reuses the same `gh` CLI and `scripts/verify.sh` contract the loop already relies on.

- **Zero target-PR mutation.** Across the entire run the target PR's comment count and head commit are provably unchanged: no inline comments, no triage replies, no resolve/unresolve mutations, and no commits pushed to its head branch. The only externally-visible artifact the run produces is the final delivery PR.
- **Workspace-only audit trail.** Because the PR can't be the comment channel, the reviewer→triage→fixer loop coordinates entirely through workspace files under `.claude/features/_pr-<N>/` (`findings.json`, `triage.json`, `state.json`, plus `.md` mirrors for human reading). That directory is gitignored — it's a local audit trail, not a committed artifact.
- **Delivery PR relation.** When we have push access to the target PR's head branch (it lives in this repo, not a fork), the delivery branch is **stacked on the target PR's head** and the delivery PR targets that head branch, so the author sees only the proposed fixes. When the target PR is from a fork / not push-accessible, it **falls back** to a delivery branch off our base branch with the body prominently linking the target PR.
- **Author as reviewer.** The original PR's author is requested as a reviewer of the delivery PR, so the fixes route back to the person who owns the change. If that request can't be made (e.g. the author is the runner, or lacks repo access), the run notes it in the PR body and continues rather than failing.
- **Self-explaining delivery.** The delivery PR body says what changed and why, what was deliberately _not_ changed (the won't-fix rationales from triage), and any out-of-scope follow-ups surfaced during review (the "later" items — stacked mode files no tracker subtasks, so these live only in the PR body).
- **Non-convergence is capped, not abandoned.** If the round cap is hit with must-fix items still unresolved, the run does **not** drop out without a deliverable. It sets `review_loop.delivery.capped = true` and still opens the delivery PR, with the unresolved must-fix items listed prominently as a punch list and a note that the cap was hit. This mirrors the in-place loop's `needs_human` exit but still gives the author the partial value.

At checkpoint 2, stacked runs exit with `review_loop.exit_reason = "delivered"`. You're never offered _Merge_ (we never merge the target PR); the options are _Done (delivery PR open)_ / _Iterate (drive another round on the delivery branch)_ / _Abandon (close the delivery PR)_. The summary surfaces the delivery PR URL, the target PR URL, the round count, the won't-fix and later lists, and whether the run was capped.

### Interactive stacked review

`--interactive` layers **Slack coordination** and a **comment-driven fix loop** on top of a `--stacked` review. It is **opt-in** and only valid with `--stacked` plus a Slack thread permalink:

```bash
/feature-review #123 --stacked --interactive https://<workspace>.slack.com/archives/Cxxxxxxxxxx/pxxxxxxxxxxxxxxxx
```

What it adds on top of plain stacked mode:

- **Slack-announced.** Before the reviewer team runs, it posts a reply to the configured thread announcing the review is starting and @-mentioning the PR author. After the delivery PR opens, it posts a second reply with the delivery PR link and a short changed / won't-fix / later summary (derived from the same triage data the delivery-PR body is built from).
- **Comment-driven monitoring loop on the delivery PR.** Once the delivery PR exists, the loop watches it for new human comments. Each new comment becomes a reply with concrete **multiple-choice options**; when the author picks one (an unambiguous option token), the loop applies that change on the delivery branch, runs `scripts/verify.sh`, and pushes. Ambiguous or absent selections are treated as "discuss" and re-prompted — a fix is never applied on a guess.
- **Never touches the target PR.** Everything above applies to the **delivery** PR / branch only. The monitoring loop reads, comments, reacts, resolves, and pushes on the delivery PR exclusively — including the careless case of a human commenting on the target PR thread, which is still answered only on the delivery PR. The target PR stays provably untouched, exactly as in plain `--stacked`.

#### The Slack target

The Slack target is a **full Slack thread permalink**, e.g. `https://<workspace>.slack.com/archives/Cxxxxxxxxxx/pxxxxxxxxxxxxxxxx`. The `/feature-review` command does **not** validate its format — it forwards the raw string to the conductor, which does a best-effort extraction of the channel ID and thread timestamp. **Target validity is established by access, not by format**: when the loop first needs the thread, it tries to reach the channel/thread and fails with a clear runtime error if it can't (unresolvable channel, missing thread, no permission, or an unparseable permalink). A malformed-looking permalink is not rejected up front — it simply fails at access time if it turns out to be unreachable.

#### Cadence — `--poll` and `--idle`

The monitoring loop is **re-entrant**: one invocation performs exactly **one poll cycle** (fetch new comments → reply / apply the chosen fix → update state → return), then returns next-wake guidance. It is **not** a daemon and does **not** sleep in-process. Continuity comes from an **external scheduler** in your environment — a cron entry, `/loop`, a scheduled-task equivalent, or just you re-running the command. Re-running `/feature-review #<PR> --stacked --interactive …` on the same PR resumes from persisted state (handled comments, awaiting-choice items, cadence, idle tracking).

Two flags override the cadence defaults:

| Flag           | Overrides                           | Default |
| -------------- | ----------------------------------- | ------- |
| `--poll <min>` | how often a cycle should run        | 5 min   |
| `--idle <min>` | idle window before a Slack heads-up | 30 min  |

Resolved values persist in `review_loop.monitoring`, so a resumed loop keeps the same cadence. If no human comment arrives within the idle window, the loop fires a **one-time** Slack heads-up to the thread (it re-arms when the next human comment lands). See [customization.md § Interactive review](./customization.md#9-interactive-review-poll-idle-and-the-slack-connector) for the configurable bot-author and handle-map knobs.

#### The Slack connector is optional

The Slack MCP connector is an **optional, runtime-only** dependency, required for `--interactive` only. **`feature-flow` stays fully installable and usable without it** — plain `--stacked` and every other flow add zero Slack dependency. The connector is probed **at runtime in the conductor** (the command cannot introspect MCP wiring), right before the first Slack post. If no usable connector is configured, the run **fails fast** at that point with the same message used for a missing Slack argument:

> `--interactive requires a Slack thread permalink (e.g. https://your.slack.com/archives/C…/p…). None was supplied.`

#### Gating and gate errors

The `/feature-review` command does only **syntactic** gating of `--interactive` (flag-combo validity) and emits two verbatim gate errors:

- **(a)** `--interactive` used without `--stacked`, or against a ticket target:

  > `--interactive requires --stacked and a bare PR number. Interactive review is only available for stacked PR review; it cannot run against a ticket target.`

- **(b)** `--interactive` / `--stacked` used with **no** Slack thread argument at all (a missing argument — _not_ a malformed permalink):

  > `--interactive requires a Slack thread permalink (e.g. https://your.slack.com/archives/C…/p…). None was supplied.`

A malformed or unreachable permalink is **not** rejected by the command. It is established as invalid by access in the conductor (the connector probe / first post), which is also where gate error (b) doubles as the "no Slack connector configured" failure described above.

#### Compliance note (outbound redaction)

All outbound text — every Slack post and every delivery-PR reply — passes through a single fail-closed redaction step before it is sent. The loop posts only code-change descriptions; it never posts raw diff, file content, or quoted comment text, and on any match against the deny-set (secrets/keys/tokens, SSNs, bank/routing/card numbers, name+account combinations) it blocks the post and surfaces a heads-up rather than posting a partially-redacted artifact.

#### At checkpoint 2

Interactive runs are stacked runs, so they exit with `review_loop.exit_reason = "delivered"` and offer the same _Done / Iterate / Abandon_ options (never _Merge_). Merge stays a human decision — the loop never auto-merges the delivery PR. If the delivery PR is merged or closed-unmerged, the loop posts a closing Slack reply and stops (it reuses `exit_reason = "delivered"` — no new exit reason).

## Resuming a workflow

Re-running `/feature <TICKET>` always resumes from the current stage in `state.json`. It will not redo a complete stage.

To **force restart** of a stage, either edit `.claude/features/<TICKET>/state.json` and set the relevant `stages.<name>.status` back to `"pending"`, or run the per-stage command directly (e.g. `/feature-plan ABC-1234`) — entering with an explicit `start_stage` re-runs that stage and overwrites its asset.

## Troubleshooting

| Symptom                                             | What to check                                                                                                                                                         |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| MCP connector fails                                 | Auth — re-run the connector's authenticate call.                                                                                                                      |
| Implementation agent stuck in verify failure loop   | Read the failure verbatim. Often a real bug — fix it manually and re-run.                                                                                             |
| PR review team posts duplicate or off-lane comments | Inspect the reviewer's summary in the round logs (`state.json:review_loop.rounds[N]`). Tune the relevant reviewer agent's `.claude/agents/*.md` if a pattern repeats. |
| Triage replies missing on some comments             | Look at `state.json:review_loop.rounds[N].triage`. Re-invoke the `pr-triage` skill manually with the round number to retry.                                           |
| Reached max rounds with unresolved will-fix items   | The workflow exits to Checkpoint 2 with `review_loop.status: needs_human`. Fix the items manually, or push the will-fix list to a new ticket and merge.               |

## Limits and known shortcomings (v1)

- The workflow assumes a single open branch / PR at a time per ticket. Multi-PR features need manual coordination.
- Cross-ticket dependencies are not modeled. If `tasks.md` requires another ticket to land first, the agent will block silently; surface this in the brief's "Dependencies" section.
- No automatic rollback. If something goes very wrong mid-implementation, you abort manually (`git reset`, `gh pr close`).
- The custom review-team agents (`architecture-reviewer`, `frontend-ux-reviewer`) ship as **skeletons**. Without project-scoped overrides, reviewer output will be generic. See the setup checklist step 4.
- Claude Code only. No Cursor / Gemini / Windsurf support in v1.
