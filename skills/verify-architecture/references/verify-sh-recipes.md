# Verify script recipes

Companion guide for the `verify-architecture` skill. Stack-specific advice and authoring guidance that doesn't belong in the skill body.

## What goes in a verify script

A solid `scripts/verify.sh` composes ~5 categories of check. Run them in this order — cheap fast checks first, slow checks last:

1. **Static type checks** — TypeScript (`tsc --noEmit`), Flow, mypy, pyright, etc.
2. **Linting** — ESLint, Biome, Ruff, golangci-lint, etc.
3. **Formatting** — Prettier, Biome, Ruff format, gofmt — anything that runs in check mode and diffs.
4. **Tests** — unit/integration tests. Optionally a fast subset and a full subset.
5. **Custom architecture rules** — project-specific scripts (typically in `scripts/arch/`) that catch structural drift not expressible in lint rules.

Copy `${CLAUDE_PLUGIN_ROOT}/references/recipes/verify.sh.example` as a starting point and replace the check list with your project's commands.

## Failure → action recipes

### TypeScript / JavaScript projects

- **`tsc --noEmit` errors**: read the diagnostic. Don't paper over with `@ts-ignore`, `@ts-expect-error`, or `as any`. If the type is genuinely unknowable (e.g. an untyped third-party API), narrow with a runtime check (a Valibot/Zod parse) so the type comes from validation, not assertion.
- **ESLint / Biome errors**: fix the rule violation. If the rule fires on legitimate code, the rule is mistuned — change the rule, not the code. Don't add `// eslint-disable-next-line` inline unless commented with a clear reason.
- **Prettier diff**: run `npx prettier --write <file>` (or `biome format --write`) and re-verify. Don't reformat code by hand.
- **Vitest / Jest failures**: read the assertion. If a snapshot test failed, look at the diff before updating snapshots — most snapshot regressions are real regressions, not snapshot staleness.

### Python projects

- **mypy / pyright errors**: similar advice — fix the type, don't `# type: ignore`. Validate at boundaries with Pydantic.
- **Ruff lint**: most violations have auto-fixes (`ruff check --fix`). Run that, then re-verify.
- **Ruff format**: `ruff format` writes; re-verify.
- **pytest failures**: read the assertion. Fixture errors usually mean a setup/teardown is broken — check `conftest.py`.

### Other stacks

The principle generalizes: read the actual error, fix the root cause, don't bypass. The `verify-architecture` skill body's failure-category table is intentionally stack-agnostic.

## Authoring custom architecture rules

Custom rules are simply scripts that:

1. Take no required args (or an optional `--format=text|json`).
2. Scan some part of the codebase.
3. Print findings.
4. Exit `0` if clean, `1` if violations found.

Three working examples ship with this plugin under `arch-rule-examples/`:

| File                         | What it catches                                                                                                                                        |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `feature-imports.ts.example` | Cross-feature imports in a feature-folder organized React app. Walks `features/<A>/**/*.{ts,tsx}` and flags any import resolving into `features/<B>/`. |
| `no-raw-fetch.ts.example`    | Raw `fetch()` / `axios` / `XMLHttpRequest` calls outside a project's data-fetching layer. Uses a path allowlist + regex.                               |
| `test-colocation.ts.example` | Tests in `__tests__/` directories or with `.spec.*` suffix, when the project's convention is colocated `.test.*`.                                      |

Each uses `fast-glob` + Node's built-in `fs` and `path` — minimal dependencies, easy to read. Adapt them by:

1. Changing the path constants at the top to match your project structure.
2. Tweaking the pattern (regex / glob) to match your conventions.
3. Hooking them into your `verify.sh`.

You can also write rules in any language. Go, Python, Rust — anything that prints text and exits with a code. The contract is the contract.

### Output contract for custom rules

For tooling integration (specifically the `pr-triage` skill, which can route violations to fix-or-defer decisions), every rule should support `--format=json` and emit:

```json
{
  "rule": "rule-name",
  "passed": true,
  "violations": [
    { "file": "path/to/file.ts", "line": 12, "message": "human-readable" }
  ]
}
```

Without this, the rule still works for humans (verify.sh shows the text output) but can't be machine-routed during PR triage.

### When to ESLint a rule vs. when to script it

ESLint (and equivalents) excels at **AST-level rules within a single file**. If your rule walks a syntax tree and can be expressed as "this AST node should/shouldn't appear here," it belongs as an ESLint custom rule or plugin.

Custom scripts under `scripts/arch/` are better when:

- The rule crosses files (e.g., "imports from feature A must not reach feature B").
- The rule examines directory structure or file naming.
- The rule needs project-specific paths that would be awkward to encode in lint config.
- You want the rule's output to be easily readable on its own.

Both can coexist. The verify script can run lint and arch rules in sequence.
