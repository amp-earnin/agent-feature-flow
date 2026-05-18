---
name: pr-triage
description: Reads all unresolved review comments on a PR, classifies each as will-fix / won't-fix / later, replies to every comment with the decision and rationale, creates tracker subtasks for "later" items, and returns the will-fix list for the implementation step.
---

# PR triage

You triage the review team's comments and decide what gets fixed in this round.

## Input

- `PR_NUMBER`: GitHub PR number.
- `TICKET` _(optional)_: tracker ticket ID. When set, "later" items become tracker subtasks of this ticket.
- `PR_WORKSPACE` _(optional)_: alternative workspace key (e.g. `_pr-123` — leading underscore makes it disjoint from any tracker ID) for PR-only review with no ticket.
- `ROUND`: review round number.

**Preconditions**:

- Exactly one of `TICKET` or `PR_WORKSPACE` must be set. If both or neither, abort with: `pr-triage: exactly one of TICKET or PR_WORKSPACE must be provided.`
- If `PR_WORKSPACE` is set, it MUST match `^_pr-[0-9]+$`. If not matched, abort with: `pr-triage: PR_WORKSPACE must match ^_pr-[0-9]+$, got: <value>.`

Workspace path: `WS = .claude/features/<TICKET or PR_WORKSPACE>/`.

## Steps

### 1. Fetch all review comments

The orchestrator's contract is: reviewers post **findings** as inline file comments (Pull Request Review Comments API) and post **"no issues found" sentinels** as issue comments (since there is no line to anchor to). Read both.

```bash
# Findings — inline file comments
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments --paginate > /tmp/pr-<PR>-r<ROUND>-inline.json
# Sentinels (and any stray issue-level findings)
gh api repos/{owner}/{repo}/issues/<PR_NUMBER>/comments --paginate > /tmp/pr-<PR>-r<ROUND>-issue.json
```

If `inline.json` is empty but you see `[<lane>] ...` content in **PR review bodies** (`gh api .../pulls/<PR_NUMBER>/reviews`), the reviewers used the wrong API — this is a contract bug, not a routing rule. STOP and surface the mismatch to the conductor rather than silently rescuing it; replying to review bodies with issue comments creates a pile of unanchored noise.

Parse `inline.json`. Each comment has `id`, `body`, `path`, `line`, `user.login`, `in_reply_to_id`.

**Filter**:

- From `issue.json`, drop any `[<lane>] No issues found` — these are sentinels confirming a lane ran clean.
- From `inline.json`, skip comments where `in_reply_to_id` is set — those are replies, not top-level findings.
- Skip comments already authored by you in a previous round (look for the triage tags `[will-fix]`, `[won't-fix]`, `[later]` at the start of body).
- If after filtering there are **zero findings**, do not post anything. Write an empty triage result and exit. Do not generate placeholder "Triage of review:" comments.

Lane-tag contract: see `${CLAUDE_PLUGIN_ROOT}/references/lane-tags.md`.

### 2. Classify each comment

For each remaining comment, decide:

| Tag           | Criteria                                                                                                                                                                                                                                                      |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **will-fix**  | Correctness bugs; security issues; violations of project-defined architecture rules (whatever the `verify-architecture` skill enforces in this project); failing tests; accessibility regressions; broken types. Anything that would justifiably block merge. |
| **won't-fix** | Style preferences without rule backing; suggestions to refactor unrelated code; nice-to-haves that don't affect correctness; concerns about code outside this PR's scope.                                                                                     |
| **later**     | Valid issues that exceed this PR's scope — e.g., "this whole helper should be moved to shared/", or "needs deeper refactor". Create follow-up work, not in-PR fix.                                                                                            |

Lean toward **will-fix** when the comment is from the `[correctness]` or `[security]` lanes. Lean toward **later** for `[arch]` issues that imply large refactors. Lean toward **won't-fix** for `[ux]` style nits without a rule citation.

### 3. Reply to each comment

For every triaged comment, post a reply on the same thread:

```bash
gh api -X POST repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments/<COMMENT_ID>/replies \
  -f body="[<tag>] <one-sentence reasoning>"
```

(Use `-f` for string values; `-F` treats the input as a typed parameter and can mangle the body. The reply endpoint requires `POST`.)

Reply format examples:

- `[will-fix] Agreed — the user can submit without an account ID, which crashes the server. Fixing.`
- `[won't-fix] This is a style preference; existing codebase mixes both patterns and we don't have a rule to enforce one.`
- `[later] Valid concern, but moving this helper crosses three feature boundaries. Created PROJ-XXXX to do it properly.`

### 4. Create tracker subtasks for "later" items

**PR-only mode** (no `TICKET`): skip subtask creation entirely — there is no tracker to file into. Your reply from step 3 is the durable record. Phrase it honestly: `[later] Out of scope for this review. No tracker is configured, so this finding is not being tracked elsewhere — surface it to a human if it matters.` Don't claim "tracking externally" when nothing is being tracked.

**Ticket mode**: for each `later` comment:

1. Use your tracker's "create issue" MCP tool (JIRA: `mcp__claude_ai_Atlassian_Rovo__createJiraIssue`) with:
   - `projectKey`: same as the original ticket's project (parse from the ticket ID's prefix).
   - `issueType`: `Task` (or `Sub-task` if the workflow uses it — check the parent's allowed issue types).
   - `summary`: `<original-ticket-id> follow-up: <short description>`
   - `description`: include the original comment body verbatim + a link to the PR comment.
   - `parent`: the original ticket ID, if subtask issuetype is used.
   - `labels`: `["tech-debt", "auto-created"]`.
2. Then update your reply to include the new tracker URL.

### 5. Return the triage result

Output a JSON object (printed to stdout, parseable by the caller):

```json
{
  "round": <ROUND>,
  "will_fix": [
    { "comment_id": ..., "path": ..., "line": ..., "summary": "..." }
  ],
  "wont_fix": [...],
  "later": [
    { "comment_id": ..., "tracker_url": "...", "summary": "..." }
  ]
}
```

### 6. Update state.json

Append this triage result to `<WS>/state.json:review_loop.rounds[<round-1>].triage`.

## Constraints

- **Reply to every comment** — never silently drop one. The author deserves to see the reasoning.
- **One issue, one comment** is the input contract. If a single comment bundles three issues, triage all three together but reply once with all three decisions.
- **Don't escalate later → will-fix** mid-loop. If you decide "later" and then realize it's actually blocking, file a fresh comment for the next round; don't rewrite history.
- For ambiguous comments, ask the conductor — but lean toward `will-fix` for correctness lanes and `later` for arch lanes when in doubt.
