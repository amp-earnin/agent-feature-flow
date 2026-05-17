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

Loop continues until `will-fix` is empty or `max_rounds` (default 5) is reached. Configure max rounds by editing `state.json:review_loop.max_rounds` before the loop starts.

## Resuming a workflow

Re-running `/feature <TICKET>` always resumes from the current stage in `state.json`. It will not redo a complete stage.

To **force restart** of a stage, edit `.claude/features/<TICKET>/state.json` and set the relevant `stages.<name>.status` back to `"pending"`.

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
