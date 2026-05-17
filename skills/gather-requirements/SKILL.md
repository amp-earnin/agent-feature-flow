---
name: gather-requirements
description: Pulls requirements from a tracker ticket and every linked source (Figma, Confluence, Slack, Google Docs) via MCP connectors. Synthesizes into a structured feature brief. Does NOT write files — returns the brief content for the brief-author skill to persist.
---

# Gather requirements

You are gathering requirements for a single tracker ticket. The output is a **distilled brief** — token-efficient summary of everything an implementation agent needs, with links back to sources for any deeper detail.

## Assumptions to verify upfront

Before fetching anything, confirm these MCP servers are configured in the user's Claude Code environment. If any are missing, **surface the gap to the conductor and continue with what's available** — don't fail the workflow.

| Source                            | MCP server (default name)                                                                | Required?                          |
| --------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------- |
| Tracker (JIRA / Linear / similar) | `mcp__claude_ai_Atlassian_Rovo__*` for JIRA; for other trackers, use the appropriate MCP | **Yes** (ticket is the entrypoint) |
| Figma designs                     | `mcp__claude_ai_Figma__*`                                                                | Optional                           |
| Confluence docs                   | `mcp__claude_ai_Atlassian_Rovo__*` (same connector)                                      | Optional                           |
| Slack threads                     | `mcp__claude_ai_Slack__*`                                                                | Optional                           |
| Google Docs / Drive               | `mcp__claude_ai_Glean__*` or `mcp__claude_ai_Google_Drive__*`                            | Optional                           |

If your tracker is not JIRA (e.g. Linear, GitHub Issues, Shortcut), substitute the equivalent MCP tool names in the steps below. Tool selection is the only thing that changes — the gather→distill→return flow stays the same.

## Input

- `TICKET`: tracker ticket ID (e.g. `ABC-1234` for JIRA-style; `ENG-42` for Linear; etc.).

## Steps

### 1. Fetch the ticket

Use the tracker's MCP "get issue" tool with the ticket ID (JIRA example: `mcp__claude_ai_Atlassian_Rovo__getJiraIssue`).

Extract:

- Title
- Description (the prose)
- Acceptance criteria (often in the description as a bullet list, or in a dedicated field)
- Status, assignee, reporter
- Parent / epic
- Labels and components
- All issue links (remote and internal): use the tracker's "get remote links" tool too (JIRA: `getJiraIssueRemoteIssueLinks`).

### 2. Identify external links

Scan the description and remote links for URLs matching:

| Source      | Pattern                        |
| ----------- | ------------------------------ | ----- | ---- | ---- | ------------ |
| Figma       | `figma.com/(design             | board | file | make | slides)/...` |
| Confluence  | `*.atlassian.net/wiki/...`     |
| Google Docs | `docs.google.com/document/...` |
| Slack       | `*.slack.com/archives/...`     |

### 3. Fetch each external source

For each link, fetch with the appropriate MCP tool:

- **Figma**: `mcp__claude_ai_Figma__get_design_context` (extract fileKey and nodeId from URL — see Figma MCP docs in system instructions). Also pull `get_screenshot` if the design has visual specifics worth referencing.
- **Confluence**: `mcp__claude_ai_Atlassian_Rovo__getConfluencePage` if you have the page ID; otherwise `mcp__claude_ai_Atlassian_Rovo__searchConfluenceUsingCql` to find it.
- **Google Docs**: use `mcp__claude_ai_Glean__read_document` with the URL (or your project's Drive MCP).
- **Slack**: use `mcp__claude_ai_Slack__slack_read_thread` if the URL points to a thread; otherwise `slack_read_channel` for recent messages.

If any source is inaccessible (auth, permissions, dead link), note it in the brief's "Open questions" section — do not block.

### 4. Distill, don't quote

For each source, extract **only what the implementer needs**. Examples:

- From Figma: list the components/screens, key states (empty, loading, error), interaction notes. Reference exact node IDs so a later agent can fetch the spec on demand. Do NOT inline pixel values or color codes — link.
- From Slack: extract decisions and constraints, not chatter. "Decided: reuse the existing TableComponent" not "Alex said maybe we could…"
- From Confluence/Docs: pull goals, scope, non-goals, dependencies. Skip background context unless it's load-bearing.

### 5. Output

Return a single markdown document matching this structure exactly (the brief-author skill applies the template; you supply the content):

```
TITLE: <ticket title>

SUMMARY: <1–2 sentences, what this delivers>

USER GOAL: <what changes for the end user>

ACCEPTANCE CRITERIA:
- <one per line>

SCOPE — IN:
- <bulleted>

SCOPE — OUT:
- <bulleted>

DESIGN NOTES:
- <distilled from Figma, with node references>

TECHNICAL NOTES:
- <distilled from existing code surface this touches; reference file paths>

DEPENDENCIES:
- <other tickets, services, feature flags>

OPEN QUESTIONS:
- <ambiguities; inaccessible sources>

SOURCE LINKS:
- Tracker: <url>
- Figma: <url> (nodeId: <id>)
- Confluence: <url>
- Slack thread: <url>
- Docs: <url>
```

Keep total length under ~800 words. If any section is empty, write `(none)`. The implementation agents will read this — not the originals — so accuracy and completeness matter more than brevity.

## Constraints

- Do not write to disk. Return the content as your final assistant message.
- Do not synthesize information not present in the sources. Mark uncertain items as open questions.
- Do not propose implementation. Implementation choices belong to Stage 3.
