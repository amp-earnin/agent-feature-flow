---
name: verify-architecture
description: Drives the consuming project's verify script (typically `scripts/verify.sh`) and interprets the output. Use after completing any implementation task before considering it done. Contracted on a verify-script interface, not on a specific stack — bring your own checks.
---

# Verify architecture

This skill is the **gate** between "code is written" and "code is done." The workflow design assumes every implementation task ends with a clean verify run before committing.

## What this skill expects

The consuming project must provide an executable verify entry point — by convention at `scripts/verify.sh` — that meets this contract:

1. **No-arg invocation** (`bash scripts/verify.sh`) runs the full check suite for the project.
2. **Quick mode** (`bash scripts/verify.sh --quick --file <path>`) runs a fast, file-scoped subset (typically lint + format on the changed file). Used by the optional PostEdit hook.
3. **Output format**: each check prints `▶ <name>` when starting, `✓ <name>` on pass, `✗ <name>` on fail. The final line is either `✓ All verification checks passed` or `✗ Verification failed`.
4. **Exit codes**: `0` if every check passed, `1` if any failed.
5. **Optional: `--skip <category>`** to disable a category (e.g., architecture rules) during interactive debugging.

A working example lives at `${CLAUDE_PLUGIN_ROOT}/references/recipes/verify.sh.example`. Copy it to your project's `scripts/verify.sh` and customize the check list.

For deeper customization advice — stack-specific failure→action recipes, how to author custom architecture rules, JSON output for tooling — see `references/verify-sh-recipes.md` in this skill's directory.

## When to invoke

- At the end of every task in `tasks.md` (before committing the task).
- After any fix in the review loop, before pushing. This is the same gate in both review modes: in stacked mode the fix-subagent runs `bash scripts/verify.sh` before committing on the delivery branch and pushing it, exactly as the in-place loop does before pushing the PR head — the contract here is reused unchanged.
- Whenever you suspect drift after a large edit.

## Steps

### 1. Run the full suite

```bash
bash scripts/verify.sh
```

Capture stdout + stderr.

### 2. Read the output

For each `✗ <name>` line, classify the failure and act:

| Failure category         | General action                                                                                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Type errors              | Fix the type. Don't suppress (`@ts-ignore` / `as any` / equivalent) unless the code is unblockable and you note it as a follow-up.                             |
| Lint errors              | Fix the rule violation. If the rule is wrong for the situation, escalate — don't disable it inline.                                                            |
| Format diff              | Run the project's format-write command (commonly `prettier --write`, `biome format --write`, `ruff format`) and re-verify.                                     |
| Test failures            | Read the assertion. Fix the test or the code — both are valid; depends on whether the test or the change is correct.                                           |
| Custom architecture rule | Read the rule's output. Each rule should describe _what_ the violation is and _how_ to fix it. See the project's `docs/architecture-rules.md` (or equivalent). |

For stack-specific recipes (TypeScript projects, Python projects, etc.) and how to author custom rules, see `references/verify-sh-recipes.md` in this skill.

### 3. Re-run after fixing

Repeat steps 1–2 until you see `✓ All verification checks passed`.

If you cannot resolve a failure after 3 attempts, **stop and surface the failure to the conductor** — do not commit code that does not pass verification.

## For machine-readable output

If your verify script's architecture rules support `--format=json` (recommended for the triage skill), invoke each rule individually. Each should print:

```json
{ "rule": "<name>", "passed": true|false, "violations": [...] }
```

The triage skill consumes this format directly. See the example rules at `references/arch-rule-examples/` in this skill.

## Quick (file-scoped) verification

If the consuming project has wired the optional PostEdit hook (see `${CLAUDE_PLUGIN_ROOT}/hooks/post-edit-verify.sh.example` and `${CLAUDE_PLUGIN_ROOT}/references/consumer-setup-checklist.md`), `verify.sh --quick --file <path>` runs automatically after every Edit/Write. You don't invoke it manually — but you must read its output and not bypass failures.

## Output

Return a single-line status to the caller: `verify: pass` or `verify: fail (<failed-check-names>)`.
