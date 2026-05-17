# CLAUDE.md

This file is for Claude Code instances loading this repository (the plugin source, not a consumer of the plugin).

## What this repo is

The source of the `feature-flow` Claude Code plugin. It is **published** for other projects to install via the plugin marketplace; you are looking at the source tree.

Repo layout follows the addyosmani/agent-skills conventions:

```
.claude-plugin/        # Plugin manifest + marketplace registration
.claude/commands/      # Slash commands (just /feature)
skills/                # Six core skills + one meta-skill
agents/                # Two reviewer personas (skeletons)
hooks/                 # SessionStart hook + a PostEdit example
references/            # Shared schemas, contracts, recipes
docs/                  # End-user documentation
```

## What you should and should not do here

### Should

- Improve clarity in skills, agents, docs.
- Generalize anywhere that still leaks stack-specific assumptions.
- Add new example architecture rules under `skills/verify-architecture/references/arch-rule-examples/`.
- Add new stack adapters for `references/recipes/verify.sh.example`.
- Keep `.example` files self-documenting (every project-specific value should be commented with `CUSTOMIZE:`).

### Should NOT

- Add new stages to the workflow. The 6-stage shape is the contract; changing it breaks consuming projects.
- Add required dependencies. Every new "you must install X" raises install friction.
- Bake project-specific patterns into the core. They belong in consuming projects.
- Couple agent prose to a specific stack outside an `<!-- EXAMPLE -->` block.

## How to verify changes

There is no automated test suite for skill prose. Verify by:

1. **Grep sanity**: skill bodies, agent skeletons, and docs should NOT contain `PAY-`, `@payroll-saas`, `packages/web/src/`, `npm -w`, or other repo-specific strings outside the `<!-- EXAMPLE -->` blocks and `.example` files.
2. **Local install smoke test**: from a separate test repo, `claude plugin marketplace add file:///path/to/this/repo` then `claude plugin install feature-flow@feature-flow-marketplace`. Confirm `/feature` resolves and all six skills + two agents appear.
3. **Dry-run a real ticket** in a consuming project that has the plugin installed.

## Common edits

| Edit                            | Files to touch                                                                                                                                       |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| New example arch rule           | `skills/verify-architecture/references/arch-rule-examples/<name>.ts.example`, `docs/architecture-rules.md`                                           |
| New customization knob          | `docs/customization.md`, plus the skill/agent that newly supports it                                                                                 |
| Reword a skill                  | Just `skills/<name>/SKILL.md`; mention in PR if it changes the contract                                                                              |
| New stack adapter for verify.sh | `references/recipes/verify.sh.example` (or a sibling for the new stack), plus a note in `skills/verify-architecture/references/verify-sh-recipes.md` |

## See also

- [CONTRIBUTING.md](./CONTRIBUTING.md) — submission process and quality bar.
- [README.md](./README.md) — user-facing overview.
