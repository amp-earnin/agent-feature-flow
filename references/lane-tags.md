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

## Why this matters

The triage skill parses comment bodies based on these prefixes. Drift from the contract breaks automatic routing. If you customize the lane structure (e.g., add a `[perf]` reviewer for performance), update both:

1. The new reviewer agent (and the `pr-review-orchestrator` skill's reviewer table).
2. The `pr-triage` skill's classification table.

Both must agree on the tag.
