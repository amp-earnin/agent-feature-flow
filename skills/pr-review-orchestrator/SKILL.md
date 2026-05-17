---
name: pr-review-orchestrator
description: Spawns the 4-agent PR review team in parallel (correctness, architecture, security, frontend/UX). Waits for all to finish posting comments, then hands off to pr-triage. Tracks rounds in state.json.
---

# PR review orchestrator

You spawn the parallel review team for the open PR and ensure all four reviewers complete before triage runs.

## Input

- `PR_NUMBER`: the GitHub PR number (e.g., `123`).
- `TICKET`: tracker ticket ID (used to locate state.json).
- `ROUND`: current review round number (1-indexed).

## Steps

### 1. Pre-flight

- Read `.claude/features/<TICKET>/state.json` to confirm we are in the `review_loop` stage and `round` matches the caller's claim.
- Fetch the PR diff: `gh pr diff <PR_NUMBER> > /tmp/pr-<PR>-r<ROUND>.diff`. Keep this local; do not pass it inline to every reviewer (token waste).
- Locate the brief: `.claude/features/<TICKET>/brief.md`.

### 2. Spawn the 4-agent review team in parallel

Use **a single message with four `Agent` tool calls** so they run concurrently. Each reviewer:

| Reviewer      | Subagent type                                                                 | Lane                                                                    |
| ------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Correctness   | `agent-skills:code-reviewer` (or your project's equivalent)                   | Bugs, logic errors, missed edge cases, regressions                      |
| Architecture  | `architecture-reviewer` (this plugin; consumer can override at project scope) | Feature boundaries, file placement, pattern consistency                 |
| Security      | `agent-skills:security-auditor` (or your project's equivalent)                | Input validation, auth, XSS, secrets, OWASP top 10                      |
| Frontend / UX | `frontend-ux-reviewer` (this plugin; consumer can override at project scope)  | Component patterns, a11y, loading/error states, design-system adherence |

Note on overrides: when both the plugin and the consuming project define an agent with the same name, Claude Code resolves the project-scoped one first. Consumers should ship project-scoped `architecture-reviewer.md` and `frontend-ux-reviewer.md` with stack-specific guidance — see the `<!-- EXAMPLE -->` blocks at the bottom of the plugin's `agents/*.md` for full reference implementations.

Prompt structure for each reviewer (substitute the lane-specific guidance):

> You are the **<LANE>** reviewer for PR #<PR_NUMBER> on branch <branch>. Read the PR diff at `/tmp/pr-<PR>-r<ROUND>.diff` and the feature brief at `.claude/features/<TICKET>/brief.md`. Find issues **only in your lane** — do not comment on other lanes' concerns.
>
> Post each issue as a separate review comment using `gh pr review <PR_NUMBER> --comment --body "..."` (one issue per `gh` call). Each comment body MUST start with the lane tag: `[<lane>]` (e.g. `[correctness]`, `[arch]`, `[security]`, `[ux]`). After the tag, write 1–3 sentences: what is wrong, where, and how to fix.
>
> If you find no issues in your lane, post a single comment: `[<lane>] No issues found in this lane.`
>
> Return a one-line summary: `<lane>: N comments posted`.

The lane-tag contract is defined in `${CLAUDE_PLUGIN_ROOT}/references/lane-tags.md`.

### 3. Wait for all four

The single-message parallel invocation will return after all four agents finish. Capture each agent's summary.

### 4. Record the round

Update `.claude/features/<TICKET>/state.json:review_loop.rounds[<round-1>]`:

```json
{
  "round": <ROUND>,
  "reviewers": {
    "correctness": "<summary>",
    "architecture": "<summary>",
    "security": "<summary>",
    "ux": "<summary>"
  },
  "comments_posted_at": "<ISO timestamp>"
}
```

### 5. Hand off to triage

Invoke the `pr-triage` skill with `PR_NUMBER`, `TICKET`, and `ROUND`. It will read the comments via `gh api`, triage each, reply, and return the `will_fix` list.

## Output

Return to the conductor: the triage result (`{ will_fix, wont_fix, later }`) verbatim.

## Constraints

- **Always spawn the four agents in a single message** so they parallelize. Sequential spawning wastes wall-clock time and breaks the design.
- Reviewers must stay in their lane. If a correctness reviewer posts an arch comment, triage will route it correctly anyway via the `[arch]` tag, but it dilutes signal.
- Do not post the diff inline to reviewers. They read it from `/tmp/pr-<PR>-r<ROUND>.diff` (local file). This saves tokens proportional to diff size × 4.
