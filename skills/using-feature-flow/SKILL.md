---
name: using-feature-flow
description: Discovers and invokes the right feature-flow skill for the task at hand. Use at session start or when a tracker ticket is the work unit; routes to /feature for end-to-end runs, or to a specific sub-skill for partial work.
---

# Using feature-flow

This meta-skill is the decision tree for the feature-flow plugin. Use it to decide which entrypoint or sub-skill applies.

## Decision tree

```
Is a tracker ticket the work unit (e.g. ABC-1234, ENG-42)?
  │
  ├── Yes, starting from scratch ─────────→ run /feature <TICKET>
  │                                          (the slash command kicks off the conductor)
  │
  ├── Yes, resuming an interrupted run ───→ run /feature <TICKET>
  │                                          (idempotent; resumes from state.json)
  │
  ├── Just need the brief, no implement ──→ invoke gather-requirements
  │                                          then feature-brief-author
  │
  ├── Have a brief, need a task plan ─────→ invoke planning skill of your choice
  │                                          (e.g. agent-skills:planning-and-task-breakdown)
  │                                          reading .claude/features/<T>/brief.md
  │
  ├── Have failing verify, need help ─────→ invoke verify-architecture
  │                                          (interprets scripts/verify.sh output)
  │
  ├── Already have an open PR, want
  │   the parallel reviewer team ─────────→ invoke pr-review-orchestrator
  │                                          (manually pass PR_NUMBER, TICKET, ROUND)
  │
  └── Have review comments, need triage ──→ invoke pr-triage
                                            (classifies + replies)
```

## Skill manifest

| Skill                    | Purpose                                                                                                            |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `feature-flow-conductor` | Orchestrator for the full 6-stage workflow. Invoked by `/feature`. Reads/writes state.json.                        |
| `gather-requirements`    | Pulls a tracker ticket + linked Figma/Confluence/Slack/Docs via MCP and distills into brief content.               |
| `feature-brief-author`   | Persists the distilled content as `brief.md` + tracker comment. Templates the canonical brief shape.               |
| `verify-architecture`    | Drives the consuming project's `scripts/verify.sh` and interprets failures. The gate between "written" and "done." |
| `pr-review-orchestrator` | Spawns the 4-agent parallel review team and hands off to triage.                                                   |
| `pr-triage`              | Classifies each reviewer comment (will-fix / won't-fix / later), replies, creates "later" subtasks in the tracker. |

## When NOT to use this plugin

- You're not in a Claude Code session, or the project doesn't use a tracker.
- The work is small enough not to warrant 6 stages + 2 checkpoints. Use the `agent-skills` plugin's standalone skills (`spec`, `plan`, `build`, `test`, `review`, `ship`) directly.
- You don't have an MCP connector to your tracker. The workflow needs at least the tracker MCP to function; everything else is optional.

## Required setup

Before first use, complete the consumer setup checklist:
`${CLAUDE_PLUGIN_ROOT}/references/consumer-setup-checklist.md`

The most common failure mode is skipping step 4 (reviewer agent overrides) — the plugin's reviewer agents are skeletons and need project-scoped customization to produce useful comments.

## See also

- `${CLAUDE_PLUGIN_ROOT}/docs/workflow-guide.md` — end-user guide.
- `${CLAUDE_PLUGIN_ROOT}/docs/customization.md` — every customization knob.
- `${CLAUDE_PLUGIN_ROOT}/docs/architecture-rules.md` — how to author project-specific verification rules.
