# Contributing to feature-flow

Thanks for considering a contribution. This file describes how to submit changes.

## What kinds of changes are welcome

- **Improvements to the existing skills** — clearer wording, tighter steps, better failure handling.
- **Generalization fixes** — places where the plugin still assumes a specific stack or tracker that it shouldn't.
- **New example arch rules** under `skills/verify-architecture/references/arch-rule-examples/` — particularly for non-React-monorepo layouts.
- **Stack adapters for the verify recipe** — additional examples covering pnpm, yarn, non-Node stacks, etc.
- **Multi-tool support** (Cursor, Gemini CLI, Windsurf) — non-trivial but on the v2 roadmap.
- **Documentation improvements** in `docs/`, `references/`, and the README.

## What probably isn't a good fit

- New top-level stages in the workflow. The 6-stage shape is load-bearing and adding stages breaks the contract that consuming projects build around.
- New required prerequisites that aren't trivially auto-detected. Each new "you must install X first" raises the install friction.
- Project-specific rules baked into the plugin core. Project-specific things go in the consuming repo, not here.

## Skill anatomy

If you're adding or modifying a skill (`skills/<name>/SKILL.md`), preserve this structure:

```
---
name: <kebab-case-name>
description: <one sentence describing when to use this>
---

# <Title>

<1–2 paragraph intro: what the skill is for, when it applies>

## Input
- <input args>

## Steps
### 1. <step>
### 2. <step>
...

## Output
<what the skill returns>

## Constraints
- <invariants the skill maintains>
```

Keep it concise. Skills are loaded into agent context — every paragraph costs tokens.

## Local setup

This repo uses Prettier for formatting, enforced via a git pre-commit hook (husky + lint-staged).

```bash
npm install
```

That installs Prettier and registers the hook. After that, staged `.md`/`.json`/`.yml`/`.yaml`/`.js`/`.ts` files are auto-formatted on every `git commit` — no manual step required. To format the whole repo on demand, run `npm run format`. CI-style check: `npm run format:check`.

Node version is pinned in `.tool-versions` (`nodejs 22.15.0`) for asdf users.

## Submitting a PR

1. Fork and branch: `feat/<short-description>` or `fix/<short-description>`.
2. Make changes. Touch only files relevant to the change.
3. Run a grep sanity check before pushing:

   ```bash
   grep -rn "PAY-" skills/ agents/ .claude/ docs/ references/  # should be empty
   grep -rn "@payroll-saas" skills/ agents/ .claude/ docs/ references/  # should be empty
   grep -rn "packages/web/src/" skills/ agents/ .claude/ docs/  # only in .example files
   ```

   `.example` files may contain stack-specific paths (that's the point). Skill bodies and docs must not.

4. Open a PR. In the description, explain:
   - What the change does.
   - Which skill/agent/doc it touches.
   - Why this generalization is correct (i.e., does the new wording cover more stacks than the old?).

5. Single concern per PR. If you have three improvements, three PRs.

## Quality bar

- **Specific**: the skill or doc says what to do, not vague guidance.
- **Verifiable**: there's a way to check it worked (passing tests, clean grep, smoke run).
- **Battle-tested**: ideally, you've run the workflow on a real ticket with the change.
- **Minimal**: no extra abstractions or hypothetical-future features.

## Reporting issues

Open a GitHub issue with:

- What you ran.
- What you expected.
- What actually happened (paste agent output where relevant).
- Your Claude Code version and plugin install method.

For security issues, do not file public issues. Email instead.
