# AGENTS.md

This file documents the agent personas shipped in this plugin's `agents/` directory.

## Shipped agents

### `architecture-reviewer`

- **Lane tag**: `[arch]`
- **Used by**: `pr-review-orchestrator` skill, as one of the four parallel PR reviewers.
- **Purpose**: review structural decisions — feature boundaries, file placement, naming, pattern consistency.
- **Status**: ships as a **skeleton**. Consuming projects MUST author a project-scoped override at `.claude/agents/architecture-reviewer.md` filled with their codebase's specifics. Without an override, reviewer output is generic.
- **Reference**: see the `<!-- EXAMPLE -->` block at the bottom of `agents/architecture-reviewer.md` for a fully-populated reviewer (Vite + React Query + TanStack Form codebase).

### `frontend-ux-reviewer`

- **Lane tag**: `[ux]`
- **Used by**: `pr-review-orchestrator` skill, as one of the four parallel PR reviewers.
- **Purpose**: review frontend craft — data fetching, forms, accessibility, loading/error states, styling, story coverage.
- **Status**: also ships as a **skeleton**. Same override pattern as `architecture-reviewer`.
- **Reference**: `<!-- EXAMPLE -->` block at the bottom of `agents/frontend-ux-reviewer.md`.

## Agents NOT shipped (relied on from elsewhere)

The plugin's `pr-review-orchestrator` skill assumes two additional reviewers exist:

- `agent-skills:code-reviewer` (for the `[correctness]` lane)
- `agent-skills:security-auditor` (for the `[security]` lane)

These come from the `addyosmani/agent-skills` plugin (`claude plugin marketplace add addyosmani/agent-skills`). If you have a different set of base agents, override `pr-review-orchestrator/SKILL.md` at the project scope and adjust the reviewer table.

## Authoring custom agents

If your project wants more than four review lanes (e.g., a `[perf]` reviewer for performance regressions), follow `frontend-ux-reviewer.md` as a template — same frontmatter shape, same lane scope / non-scope / how-to-post-comments / return structure. Then:

1. Add the new agent to your project's `.claude/agents/<name>.md`.
2. Override `pr-review-orchestrator/SKILL.md` to include the new reviewer in the parallel call.
3. Override `pr-triage/SKILL.md` with classification rules for the new tag.

See [docs/customization.md § Adding or removing review lanes](./docs/customization.md) for the full process.

## Resolution order

Claude Code resolves agents by name, preferring **project-scoped** (`.claude/agents/` in the host repo) over **plugin-scoped** (`agents/` in this plugin). So a project's local `architecture-reviewer.md` overrides the plugin's skeleton automatically.
