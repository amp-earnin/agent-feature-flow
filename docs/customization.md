# Customization

The feature-flow plugin is intentionally generic. Most projects need to customize a few things to get good results. This page enumerates them.

## 1. Ticket-ID pattern

By default, the `/feature` command validates `$ARGUMENTS` against the JIRA-style regex `^[A-Z]+-\d+$`. To use a different shape:

1. Copy the plugin's slash command to your project: `cp <plugin>/.claude/commands/feature.md .claude/commands/feature.md`.
2. Edit the regex comment in step 1 of "Your job in this turn" to match your tracker's ID shape.

Examples:

| Tracker                | Typical pattern     |
| ---------------------- | ------------------- |
| JIRA, Shortcut, Linear | `^[A-Z]+-\d+$`      |
| GitHub Issues          | `^#\d+$` or `^\d+$` |
| Internal numeric IDs   | `^\d+$`             |

The override at `.claude/commands/feature.md` takes precedence over the plugin's version.

## 2. Tracker (non-JIRA)

The plugin defaults reference JIRA-style operations via the Atlassian Rovo MCP. To use a different tracker:

1. Install your tracker's MCP server (Linear, GitHub Issues, Shortcut, monday.com, etc.).
2. In a project-scoped copy of `skills/gather-requirements/SKILL.md` (write at `.claude/skills/gather-requirements/SKILL.md` in your project — overrides the plugin's), swap the `mcp__claude_ai_Atlassian_Rovo__*` tool names for your tracker's equivalents.
3. Same swap in `skills/feature-brief-author/SKILL.md` (for the "post comment" step) and `skills/pr-triage/SKILL.md` (for the "create subtask" step).

The structure of the workflow doesn't change — only the MCP tool names do.

## 3. Stack — verify.sh

The verify-architecture skill drives `scripts/verify.sh`. The example recipe at `${CLAUDE_PLUGIN_ROOT}/references/recipes/verify.sh.example` is set up for an npm-based TypeScript project. Common adaptations:

### pnpm or yarn workspaces

Replace `npm run` with `pnpm run` or `yarn` in each `run` call.

### Monorepo with scoped commands

If your typecheck/lint commands are per-package:

```bash
run "TypeScript (web)"  pnpm --filter @org/web run typecheck
run "TypeScript (api)"  pnpm --filter @org/api run typecheck
run "ESLint"            pnpm run lint
```

### Non-Node stacks

The structure (`▶`/`✓`/`✗` markers, exit codes, --quick mode) is language-agnostic. Use whatever your stack requires:

```bash
run "mypy"    mypy src/
run "ruff"    ruff check src/
run "pytest"  pytest -q
```

The `verify-architecture` skill only cares about the contract — print markers, exit non-zero on fail. See `${CLAUDE_PLUGIN_ROOT}/skills/verify-architecture/references/verify-sh-recipes.md` for more.

## 4. Reviewer agents (the most important customization)

The plugin ships `architecture-reviewer` and `frontend-ux-reviewer` as **skeletons**. Without project-scoped overrides, they produce generic comments. Write `.claude/agents/architecture-reviewer.md` and `.claude/agents/frontend-ux-reviewer.md` in your project filled with your codebase's specifics:

- For `architecture-reviewer`: your folder structure, naming conventions, the executable rules in `scripts/arch/`, your chosen patterns (data fetching, forms, state, HTTP).
- For `frontend-ux-reviewer`: your component library, your data-fetching/form/styling libraries, your a11y bar, your story coverage policy.

The plugin agents include `<!-- EXAMPLE -->` blocks at the bottom with fully-populated reviewer content for a Vite + React Query + TanStack Form codebase. Copy those into your override if your stack overlaps.

## 5. Adding or removing review lanes

The default workflow uses 4 reviewers (correctness, arch, security, ux). To add a 5th lane (e.g., `[perf]`):

1. Create a project-scoped `frontend-ux-reviewer.md` (or a new `performance-reviewer.md`) at `.claude/agents/`.
2. Override `pr-review-orchestrator/SKILL.md` at `.claude/skills/` to add the new agent to the parallel review-team call. Update the reviewers table.
3. Override `pr-triage/SKILL.md` at `.claude/skills/` to add classification rules for the new tag.
4. Update your `${CLAUDE_PLUGIN_ROOT}/references/lane-tags.md` mental model accordingly.

To remove a lane, drop it from the orchestrator and adjust triage. The triage skill is robust to fewer lanes — it processes whatever tags it finds.

## 6. State directory location

By default, workflow state lives at `.claude/features/<TICKET>/`. If you prefer somewhere else (e.g., `.workflows/<TICKET>/`):

1. Override `feature-flow-conductor/SKILL.md` at `.claude/skills/` with your preferred path. The path appears in the "Workspace" section and a few other places — search and replace.
2. Add the new path to your `.gitignore`.

## 7. Max review rounds

Default is 5. To change globally:

- In the consuming project's `feature-flow-conductor/SKILL.md` override, change the schema's `max_rounds: 5` initial value.

To change per-run, edit `.claude/features/<TICKET>/state.json` before Stage 5 begins.

The cap applies identically in stacked-pr review mode (`/feature-review #<PR> --stacked`): hitting it doesn't abort the run — it sets `review_loop.delivery.capped = true` and still opens the delivery PR with the unresolved must-fix items as a punch list. See [workflow-guide.md § Stacked-pr review mode](./workflow-guide.md#stacked-pr-review-mode).

## 8. PR title / body format

The conductor's Stage 4 specifies `Title format: <TICKET>: <brief title>`. To use a different convention (e.g., your repo's conventional-commit style):

1. Override `feature-flow-conductor/SKILL.md` at `.claude/skills/`.
2. Adjust the title and body template in Stage 4.

## 9. Interactive review (poll, idle, and the Slack connector)

`--interactive` adds Slack coordination and a comment-driven fix loop to a stacked review. It is opt-in and only valid with `--stacked` plus a Slack thread permalink. See [workflow-guide.md § Interactive stacked review](./workflow-guide.md#interactive-stacked-review) for the full behavior; the knobs below are what you configure.

### The Slack connector is optional

The Slack MCP connector is an **optional, runtime-only** dependency, required for `--interactive` only. The plugin stays installable and fully usable without it — plain `--stacked` and every other flow add **zero** Slack dependency. The connector is probed at runtime in the conductor (not at command parse time) before the first Slack post; if none is configured, the interactive run fails fast there. To enable interactive review, install any Slack MCP server in the consuming environment — the conductor discovers it at runtime and references no specific connector tool name.

### Cadence — `--poll` / `--idle`

The monitoring loop runs one poll cycle per invocation (continuity comes from an external scheduler — cron, `/loop`, or a scheduled-task equivalent). Two flags override the cadence defaults persisted in `review_loop.monitoring`:

| Flag           | State field                        | Default |
| -------------- | ---------------------------------- | ------- |
| `--poll <min>` | `monitoring.poll_minutes`          | `5`     |
| `--idle <min>` | `monitoring.idle_deadline_minutes` | `30`    |

The flag value overrides the default, and the resolved value is persisted so a resumed loop keeps the same cadence. To change the defaults globally, edit them in a project-scoped `feature-flow-conductor/SKILL.md` override; to change per-run, pass the flags (or edit `state.json:review_loop.monitoring` before the loop starts).

### Ignored bot authors

`review_loop.monitoring.ignored_bot_authors` is a configurable list of GitHub logins the monitoring loop skips when scanning the delivery PR for new human comments (default `[]`). Comments from `user.type == "Bot"` and from the agent's own login (`review_loop.bot_identity`) are always skipped automatically; this list is for **human-typed** bot-style accounts you want ignored.

```jsonc
// in .claude/features/_pr-<N>/state.json, under review_loop.monitoring
"ignored_bot_authors": ["coderabbitai[bot]"] // EXAMPLE — replace with your own review-bot logins; default is []
```

### GitHub → Slack handle map

`review_loop.monitoring.github_to_slack_handles` maps a PR author's GitHub login to a Slack handle for the pre-review @-mention (nullable; default `null`). If the map is absent or has no entry for the author, the loop posts the plain GitHub username with no @-mention — it never blocks the loop on a missing mapping.

```jsonc
// in .claude/features/_pr-<N>/state.json, under review_loop.monitoring
"github_to_slack_handles": { "octocat": "U01EXAMPLE" } // EXAMPLE — map your GitHub logins to Slack user IDs
```

---

## What you cannot customize (by design)

- The 2-checkpoint structure. Adding or removing human checkpoints fundamentally changes the workflow contract; it's not parameterized.
- The fresh-context per-stage model. Stages are isolated subagents intentionally — see [workflow-guide.md § Token-optimization design](./workflow-guide.md#token-optimization-design-why-the-workflow-looks-like-this).
- The verify-script contract (markers, exit codes, --quick mode). The skill assumes them; breaking them breaks the workflow.
- The 6-stage shape. Stacked-pr review mode (`--stacked`) is a _mode_ of the existing review loop (Stage 5), selected by the `review_loop.review_mode` discriminator — not a new stage. It reuses the same lanes, triage, and `scripts/verify.sh` gate, and adds no new required dependencies (just the `gh` CLI the loop already uses). The non-invasive guarantee (target PR provably untouched) and the separate delivery PR are part of the mode's contract, not knobs. `--interactive` is likewise a flag layered onto Stage 5 (Slack posts + a comment-driven monitoring loop on the delivery PR), not a new stage — the cadence and the bot-author / handle-map knobs above are the only customizable parts; the delivery-PR-only invariant and the fail-closed outbound redaction are part of the contract, not knobs.
