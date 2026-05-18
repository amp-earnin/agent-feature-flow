# feature-flow

> Ticket in → merged PR out. An agentic feature workflow for Claude Code, with two human checkpoints.

`feature-flow` is a Claude Code plugin that drives an end-to-end software feature from a tracker ticket through code, PR, and review-loop to merge. Engineers approve at exactly two points: after the **brief** (Stage 1) and before **merge** (Stage 6). Everything else runs autonomously.

## What it does

```
/feature ABC-1234
   │
   ▼  Stage 1 · gather-requirements  (subagent, MCP: tracker / Figma / Slack / Docs)
   │     emits: .claude/features/ABC-1234/brief.md  ← also posted as tracker comment
   │
   ◉  HUMAN CHECKPOINT 1 — approve brief
   │
   ▼  Stage 2 · plan       (subagent → planning skill)
   ▼  Stage 3 · implement  (one subagent per task; verify.sh gates each commit)
   ▼  Stage 4 · open PR    (gh CLI; body links the brief + tracker)
   ▼  Stage 5 · review loop (max 5 rounds)
   │     a. parallel Agent calls × 4: correctness · arch · security · ux
   │     b. triage: classify will-fix / won't-fix / later · reply · subtask "later"
   │     c. if any will-fix and round<max → fix → push → goto (a)
   │
   ◉  HUMAN CHECKPOINT 2 — merge or iterate
```

## Design principles

1. **Token optimization** — each stage runs in a fresh-context subagent that reads only the previous stage's output. The brief is the canonical contract.
2. **Executable verification** — every architecture rule is a script the agent can run, not a paragraph in a doc. Code doesn't commit if `verify.sh` fails.
3. **Parallel reviewer team** — N parallel agents post tagged comments, one issue per comment. A triage subagent classifies, replies, and creates "later" tickets automatically.
4. **Minimal human-in-the-loop** — exactly two checkpoints, deliberately. More checkpoints break the autonomy contract.

## Install

```bash
claude plugin marketplace add amp-earnin/agent-feature-flow
claude plugin install feature-flow@feature-flow-marketplace
```

After install, complete the [consumer setup checklist](./references/consumer-setup-checklist.md):

1. Authenticate your tracker's MCP server (JIRA, Linear, etc.).
2. Copy [`references/recipes/verify.sh.example`](./references/recipes/verify.sh.example) to your repo's `scripts/verify.sh` and customize.
3. (Optional) Wire the PostEdit hook for tight feedback.
4. **Override the two reviewer agents** with project-scoped versions filled in for your stack.
5. Add `.claude/features/` to `.gitignore`.

## Quick start

After setup:

```bash
/feature ABC-1234
```

The conductor will run Stage 1, then pause for your approval. From there, approve the brief and let the workflow run.

### Run a single stage

Each stage has its own command. By default it runs **only that stage** and stops; pass `--continue` to run that stage plus everything downstream.

| Command                       | Enters at      | Requires                  |
| ----------------------------- | -------------- | ------------------------- |
| `/feature-brief ABC-1234`     | gather + brief | nothing (fresh start)     |
| `/feature-plan ABC-1234`      | plan           | `brief.md`                |
| `/feature-implement ABC-1234` | implement      | `brief.md` + `tasks.md`   |
| `/feature-pr ABC-1234`        | open PR        | feature branch w/ commits |
| `/feature-review ABC-1234`    | review loop    | open PR                   |
| `/feature-review #123`        | review loop    | open PR (PR-only mode)    |

If a prerequisite is missing, the command fails with instructions — it does NOT auto-run upstream stages. Write the artifact yourself or run the upstream command. Per-ticket artifacts live in `.claude/features/<TICKET>/`.

### Reviewing any PR (no ticket needed)

`/feature-review` also accepts a bare PR number (`#123`) — useful for reviewing an external contributor's PR or any change that did not originate from this workflow. PR-only mode:

- Workspace is `.claude/features/_pr-<NUMBER>/` (leading underscore avoids collisions with tracker IDs).
- Skips brief / plan / implement. PR title + body act as intent.
- **Auto-fix loop is gated on branch ownership**. If the head branch lives in this repo (and `gh pr checkout` succeeds), the convergence loop runs: review → fix → re-review until reviewers find nothing or `max_rounds` (default 5) is hit. If the PR is from a fork or otherwise un-pushable, the loop exits after one round with the will-fix list as a punch list for you to relay to the PR author.
- Requires `.claude/features/` to be in `.gitignore` (PR bodies can contain sensitive content). If it isn't, the conductor aborts with:

  > Refusing to write PR content to a tracked path. Add `.claude/features/` to `.gitignore` and retry.

Example — write your own brief, then jump straight into planning + everything downstream:

```bash
$EDITOR .claude/features/ABC-1234/brief.md
/feature-plan ABC-1234 --continue
```

## What ships in this plugin

| Component                  | Path                                                                                                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Slash commands             | `.claude/commands/feature.md` (full pipeline) + `feature-brief.md`, `feature-plan.md`, `feature-implement.md`, `feature-pr.md`, `feature-review.md` (per-stage)                       |
| Conductor + 5 stage skills | `skills/feature-flow-conductor/`, `skills/gather-requirements/`, `skills/feature-brief-author/`, `skills/verify-architecture/`, `skills/pr-review-orchestrator/`, `skills/pr-triage/` |
| Meta-skill (discovery)     | `skills/using-feature-flow/SKILL.md`                                                                                                                                                  |
| Review team personas       | `agents/architecture-reviewer.md`, `agents/frontend-ux-reviewer.md` (skeletons — override per project)                                                                                |
| Hook recipe                | `hooks/post-edit-verify.sh.example` (consumer-side wiring; see setup step 3)                                                                                                          |
| Verify-script recipe       | `references/recipes/verify.sh.example`                                                                                                                                                |
| Three example arch rules   | `skills/verify-architecture/references/arch-rule-examples/`                                                                                                                           |
| State schema               | `references/state-schema.json`                                                                                                                                                        |
| Lane-tag contract          | `references/lane-tags.md`                                                                                                                                                             |
| Tracker-comment marker     | `references/jira-comment-marker.md`                                                                                                                                                   |

## Prerequisites

- **Claude Code** (this plugin is Claude Code-only in v1; no Cursor / Gemini / Windsurf support yet).
- A tracker MCP server authenticated in your Claude Code config:
  - JIRA: Atlassian Rovo
  - Linear / Shortcut / GitHub Issues / etc.: their respective MCPs
- The `addyosmani/agent-skills` plugin (for `code-reviewer`, `security-auditor`, and `planning-and-task-breakdown` skills). Install with `claude plugin marketplace add addyosmani/agent-skills`. Optional but recommended.
- A repo with `gh` CLI configured (for PR operations).

Optional MCPs that improve the brief:

- `figma` — design context
- `slack` — referenced threads
- `glean` or `google-drive` — design docs

## Documentation

- **[Workflow guide](./docs/workflow-guide.md)** — usage, what each stage does, the two checkpoints, troubleshooting.
- **[Customization](./docs/customization.md)** — every knob you can turn (ticket pattern, tracker, stack, reviewer agents, lanes).
- **[Authoring arch rules](./docs/architecture-rules.md)** — how to write project-specific verification scripts that integrate with `verify-architecture`.
- **[Consumer setup checklist](./references/consumer-setup-checklist.md)** — step-by-step host-repo wiring.
- **[Lane-tag contract](./references/lane-tags.md)** — `[correctness] / [arch] / [security] / [ux]` and the triage tags.

## Compatibility

- **Claude Code**: v1.x
- **Other tools**: Not in v1. The skill bodies are agent-agnostic prose, so adapter layers for Cursor / Gemini CLI / Windsurf are conceivable in future versions, but no work has been done.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). PRs welcome; the bar is: specific, verifiable, useful, minimal.

## License

MIT. See [LICENSE](./LICENSE).
