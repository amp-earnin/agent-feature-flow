---
name: pr-review-orchestrator
description: Spawns the 4-agent PR review team in parallel (correctness, architecture, security, frontend/UX). Waits for all to finish posting comments, then hands off to pr-triage. Tracks rounds in state.json.
---

# PR review orchestrator

You spawn the parallel review team for the open PR and ensure all four reviewers complete before triage runs.

## Input

- `PR_NUMBER`: the GitHub PR number (e.g., `123`).
- `TICKET` _(optional)_: tracker ticket ID. Used to locate the feature workspace at `.claude/features/<TICKET>/`.
- `PR_WORKSPACE` _(optional)_: alternative workspace key (e.g. `pr-123`) for PR-only review with no ticket. Exactly one of `TICKET` or `PR_WORKSPACE` must be provided.
- `ROUND`: current review round number (1-indexed).

## Steps

### 1. Pre-flight

- Workspace path: `WS = .claude/features/<TICKET or PR_WORKSPACE>/`.
- Read `<WS>/state.json` to confirm we are in the `review_loop` stage and `round` matches the caller's claim.
- Fetch the PR diff: `gh pr diff <PR_NUMBER> > /tmp/pr-<PR>-r<ROUND>.diff`. Keep this local; do not pass it inline to every reviewer (token waste).
- Capture the PR's head commit SHA — reviewers need it to anchor inline comments: `HEAD_SHA=$(gh pr view <PR_NUMBER> --json headRefOid -q .headRefOid)`. Pass it to each reviewer.
- Locate the context document:
  - If `<WS>/brief.md` exists, use it (full feature brief).
  - Else use `<WS>/pr-context.md` (PR title + body, written by the conductor in PR-only mode).

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

> You are the **<LANE>** reviewer for PR #<PR_NUMBER> on branch <branch> (head SHA `<HEAD_SHA>`). Read the PR diff at `/tmp/pr-<PR>-r<ROUND>.diff` and the context document at `<WS>/brief.md` (or `<WS>/pr-context.md` if there is no brief — PR-only review mode means you have only the PR title and body as intent). Find issues **only in your lane** — do not comment on other lanes' concerns. In PR-only mode, do not flag missing-brief or scope-ambiguity issues — assume the PR's stated scope is the truth.
>
> **Post each issue as an inline file comment anchored to a specific line in the diff.** Use the GitHub Pull Request Review Comments API — NOT `gh pr review --comment`, which creates a top-level review body that the triage step cannot read.
>
> For each finding, run:
>
> ```bash
> gh api -X POST repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments \
>   -f body="[<lane>] <1–3 sentences: what is wrong and how to fix>" \
>   -f commit_id="<HEAD_SHA>" \
>   -f path="<file path from diff>" \
>   -F line=<line number in the new file> \
>   -f side="RIGHT"
> ```
>
> Each `body` MUST start with the lane tag: `[<lane>]` (e.g. `[correctness]`, `[arch]`, `[security]`, `[ux]`). One finding per call. Pick the most relevant new-file line from the diff — for findings that span a range, anchor to the first line and reference the range in the body.
>
> If you find no issues in your lane, post a single **issue comment** (not file-anchored, since there's nothing to anchor to):
>
> ```bash
> gh pr comment <PR_NUMBER> --body "[<lane>] No issues found in this lane."
> ```
>
> Return a one-line summary: `<lane>: N comments posted`.

The lane-tag contract is defined in `${CLAUDE_PLUGIN_ROOT}/references/lane-tags.md`.

### 3. Wait for all four

The single-message parallel invocation will return after all four agents finish. Capture each agent's summary.

### 4. Record the round

Update `<WS>/state.json:review_loop.rounds[<round-1>]`:

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

Invoke the `pr-triage` skill with `PR_NUMBER`, `ROUND`, and the same workspace identifier you received (`TICKET` or `PR_WORKSPACE`). It will read the comments via `gh api`, triage each, reply, and return the `will_fix` list.

## Output

Return to the conductor: the triage result (`{ will_fix, wont_fix, later }`) verbatim.

## Constraints

- **Always spawn the four agents in a single message** so they parallelize. Sequential spawning wastes wall-clock time and breaks the design.
- Reviewers must stay in their lane. If a correctness reviewer posts an arch comment, triage will route it correctly anyway via the `[arch]` tag, but it dilutes signal.
- Do not post the diff inline to reviewers. They read it from `/tmp/pr-<PR>-r<ROUND>.diff` (local file). This saves tokens proportional to diff size × 4.
