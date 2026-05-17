---
name: pr-triage
description: Reads all unresolved review comments on a PR, classifies each as will-fix / won't-fix / later, replies to every comment with the decision and rationale, creates tracker subtasks for "later" items, and returns the will-fix list for the implementation step.
---

# PR triage

You triage the review team's comments and decide what gets fixed in this round.

## Input

- `PR_NUMBER`: GitHub PR number.
- `TICKET`: tracker ticket ID.
- `ROUND`: review round number.

## Steps

### 1. Fetch all review comments

```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments --paginate > /tmp/pr-<PR>-r<ROUND>-comments.json
```

Parse the JSON. Each comment has `id`, `body`, `path`, `line`, `user.login`, `in_reply_to_id`.

**Filter**:

- Skip comments where `body` starts with `[<lane>] No issues found` — these are sentinels, not issues.
- Skip comments where `in_reply_to_id` is set — those are replies, not top-level findings.
- Skip comments already authored by you in a previous round (look for the triage tags `[will-fix]`, `[won't-fix]`, `[later]` at the start of body).

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
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments/<COMMENT_ID>/replies \
  -F body="[<tag>] <one-sentence reasoning>"
```

Reply format examples:

- `[will-fix] Agreed — the user can submit without an account ID, which crashes the server. Fixing.`
- `[won't-fix] This is a style preference; existing codebase mixes both patterns and we don't have a rule to enforce one.`
- `[later] Valid concern, but moving this helper crosses three feature boundaries. Created PROJ-XXXX to do it properly.`

### 4. Create tracker subtasks for "later" items

For each `later` comment:

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

Append this triage result to `.claude/features/<TICKET>/state.json:review_loop.rounds[<round-1>].triage`.

## Constraints

- **Reply to every comment** — never silently drop one. The author deserves to see the reasoning.
- **One issue, one comment** is the input contract. If a single comment bundles three issues, triage all three together but reply once with all three decisions.
- **Don't escalate later → will-fix** mid-loop. If you decide "later" and then realize it's actually blocking, file a fresh comment for the next round; don't rewrite history.
- For ambiguous comments, ask the conductor — but lean toward `will-fix` for correctness lanes and `later` for arch lanes when in doubt.
