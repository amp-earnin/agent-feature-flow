# Lane tag contract

PR review comments and triage replies use `[<tag>]` prefixes so the workflow can route them programmatically. The contract is small but strict.

## Reviewer lanes

Each reviewer prefixes every comment with one of these tags:

| Tag             | Owner                                                        | Scope                                                                  |
| --------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------- |
| `[correctness]` | Correctness reviewer (default: `agent-skills:code-reviewer`) | Bugs, logic errors, missed edge cases, regressions                     |
| `[arch]`        | Architecture reviewer (this plugin: `architecture-reviewer`) | Feature boundaries, file placement, naming, pattern consistency        |
| `[security]`    | Security reviewer (default: `agent-skills:security-auditor`) | Input validation, auth, XSS, secrets, OWASP top 10                     |
| `[ux]`          | Frontend/UX reviewer (this plugin: `frontend-ux-reviewer`)   | Data fetching, forms, a11y, loading/error states, styling, composition |

Reviewers MUST stay in their lane. If a reviewer sees a problem outside its lane, it leaves the comment to the appropriate other lane.

If a reviewer finds nothing in its lane, it posts ONE sentinel comment: `[<lane>] No issues found in this lane.`

## Triage tags

The `pr-triage` skill replies to every reviewer comment with one of these tags:

| Tag           | Meaning                                                                                                                       |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `[will-fix]`  | Will be fixed in this PR before merge.                                                                                        |
| `[won't-fix]` | Disagreement with the reviewer; reply includes reasoning.                                                                     |
| `[later]`     | Valid issue but out of scope for this PR; a follow-up tracker ticket has been created. The reply includes the new ticket URL. |

Every original comment gets exactly one reply. Triage never escalates `[later]` → `[will-fix]` mid-loop — a fresh comment must be filed in the next round if the assessment changes.

## Workspace-file coordination (stacked mode)

In `--stacked` review mode (`review_loop.review_mode = "stacked"`) the target PR is
**never mutated** — no inline comments, no triage replies, no resolve/unresolve
mutations, no pushed commits. The reviewer↔triage↔fixer loop therefore cannot use the
PR as its comment channel. Instead it coordinates entirely through **workspace files**
under the run's workspace directory `.claude/features/_pr-<N>/` (where `<N>` is the
target PR number). This section is the single source of truth for those file shapes;
the orchestrator, triage, and fix-subagent contracts reference it rather than
re-defining the shape.

The same lane tags above still apply — but the tag is written into the workspace
finding record, not into a PR comment body.

### Findings record — `findings.json` (mirrored to `findings.md` for human reading)

Written by `pr-review-orchestrator`'s reviewers (one entry per finding) and read back
during Step A re-review. An array of finding objects:

| Field            | Type    | Meaning                                                                                                  |
| ---------------- | ------- | -------------------------------------------------------------------------------------------------------- |
| `id`             | string  | Stable workspace finding id (the stacked-mode analogue of a GitHub `thread_id`). Unique within the run.  |
| `lane`           | string  | One of the reviewer lane tags above (`correctness` / `arch` / `security` / `ux`), without the brackets.  |
| `path`           | string  | File path the finding anchors to. The fixer uses `path:line` as the primary fix locator.                 |
| `line`           | integer | Line in the new file the finding anchors to.                                                             |
| `body`           | string  | The finding text (what the reviewer would have posted as a PR comment).                                  |
| `round`          | integer | Review round (1-based) the finding was raised in.                                                        |

These carry the same information the GitHub-comment path carries today (lane, path,
line, summary, and a stable finding/thread id) — only the transport changes.

### Triage record — `triage.json` (mirrored to `triage.md` for human reading)

Written by `pr-triage` (one entry per finding it classifies) and read by the
fix-subagent. An array of triage decision objects:

| Field            | Type    | Meaning                                                                                                  |
| ---------------- | ------- | -------------------------------------------------------------------------------------------------------- |
| `id`             | string  | The `findings.json` finding id this decision applies to.                                                 |
| `lane`           | string  | Copied from the finding for convenience.                                                                 |
| `path`           | string  | Copied from the finding — the fixer's locator.                                                           |
| `line`           | integer | Copied from the finding — the fixer's locator.                                                           |
| `classification` | string  | One of the triage tags above (`will-fix` / `won't-fix` / `later`), without the brackets.                 |
| `rationale`      | string  | The reasoning that would have been the triage reply body. won't-fix / later rationales feed the delivery PR's "what was deliberately not changed" section. |
| `round`          | integer | Round the decision was made in.                                                                          |

In stacked mode the fixer marks a finding resolved by updating its triage record entry
in `triage.json` — **not** by calling `resolveReviewThread` on the target PR.

## Why this matters

The triage skill parses comment bodies based on these prefixes. Drift from the contract breaks automatic routing. If you customize the lane structure (e.g., add a `[perf]` reviewer for performance), update both:

1. The new reviewer agent (and the `pr-review-orchestrator` skill's reviewer table).
2. The `pr-triage` skill's classification table.

Both must agree on the tag.

The same applies to the workspace-file shapes above: orchestrator, triage, and the
fix-subagent must agree on the `findings.json` / `triage.json` field names. Change them
in one place (here) and the consuming skills follow.
