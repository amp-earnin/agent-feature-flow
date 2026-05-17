# Authoring executable architecture rules

This guide explains how to author project-specific architecture rules that integrate with the `verify-architecture` skill. The plugin ships three example rules as starting points; you adapt them or write your own.

## The contract

An architecture rule is any executable that:

1. Takes no required args (an optional `--format=text|json` flag is recommended).
2. Scans some part of the codebase.
3. Prints findings to stdout.
4. Exits `0` if clean, `1` if violations found.

The implementation can be in any language — TypeScript, Python, Go, shell. The example rules are TypeScript (run via `npx tsx`) because that's the most common stack for Claude Code projects.

## Where rules live

By convention: `scripts/arch/<rule-name>.<ext>`.

Hook them into `scripts/verify.sh` so they run as part of the verify suite. Example block (already present in the verify.sh recipe):

```bash
if [[ "$SKIP" != "arch" ]]; then
  run "arch: feature imports"  npx tsx scripts/arch/feature-imports.ts
  run "arch: no raw fetch"     npx tsx scripts/arch/no-raw-fetch.ts
  run "arch: test colocation"  npx tsx scripts/arch/test-colocation.ts
fi
```

## Example rules (shipped with this plugin)

Three working examples live at `${CLAUDE_PLUGIN_ROOT}/skills/verify-architecture/references/arch-rule-examples/`. Each is a teaching artifact — fully functional for a Vite + React + monorepo layout, with `CUSTOMIZE:` comments calling out the paths and patterns you'll need to change for your own project.

### Example 1 — `feature-imports.ts.example` — Feature folder import boundaries

**What it enforces**: a file inside `<features-root>/<A>/` may not import from `<features-root>/<B>/` when `A !== B`. Imports within the same feature folder are fine. Imports from shared/, models/, queries/, external packages, and top-level helpers are fine.

**Why**: cross-feature coupling makes features into a graph instead of leaves. When feature A depends on feature B's internals, every change to B risks breaking A in non-obvious ways. The principle holds for any monorepo or feature-folder organization.

**Check both**:

- Relative imports: `import { Foo } from "../../other-feature/utils/foo"`
- Aliased imports: `import { Foo } from "#src/features/other-feature/utils/foo"`

**Override**: there is intentionally no inline override. If a feature genuinely needs something from another feature, the right answer is to move the dependency into shared/ or models/. If you have a case where neither feels right, raise it in design review before adding the import.

**Adapt by**: changing the `FEATURES_ROOT` and `SRC_ROOT` constants at the top, and the alias prefix (`#src/`) in `resolveImport()`.

### Example 2 — `no-raw-fetch.ts.example` — No raw HTTP clients

**What it enforces**: no `fetch(`, `axios`, `XMLHttpRequest`, or `new Request(` outside an allowed list of directories (typically your data-fetching layer, mocks, test setup, and shared HTTP utilities).

**Why**: routing all HTTP through a generated client (e.g., openapi-typescript) or a typed wrapper gets you type safety, consistent caching/error handling, and a single seam for the mock layer. Raw HTTP bypasses all of that.

**Override**: no inline override. If you genuinely need a raw fetch (e.g., uploading a file with unusual semantics the generated client can't express), put the wrapper in your shared HTTP layer so it lives next to other low-level utilities.

**Adapt by**: changing `ALLOWED_PATH_PATTERNS`, `ALLOWED_FILE_PATTERNS`, and `BANNED_PATTERNS` for your project's HTTP conventions.

### Example 3 — `test-colocation.ts.example` — Test naming and location

**What it enforces**:

- No `__tests__/` directories under your source roots.
- No `*.spec.{ts,tsx,js,jsx}` files; only `*.test.*`.

**Why**: pick a convention and stick with it. The plugin's example enforces colocation (`Foo.tsx` + `Foo.test.tsx`) with `.test.*` suffix. Your project may prefer the opposite — adapt the rule to enforce whichever you've chosen.

**Out of v1 scope**: this example does _not_ require a test to exist for every source file. Adding that check often creates immediate noise; it's a follow-up for after baseline coverage is in place.

**Adapt by**: changing `SCAN_ROOTS` to your source directories. If your project's convention is the opposite (specs in `__tests__/`), flip the violations: error on `.test.*` outside `__tests__/`.

## Output contract for tooling

For the `pr-triage` skill to route violations to fix-or-defer decisions, every rule should support `--format=json` and emit:

```json
{
  "rule": "rule-name",
  "passed": true,
  "violations": [
    { "file": "path/to/file.ts", "line": 12, "message": "human-readable" }
  ]
}
```

Without this, the rule still works for humans (`verify.sh` shows the text output) but can't be machine-routed during PR triage.

## Authoring a new rule

1. Copy one of the example files to `scripts/arch/<rule-name>.ts` (or your language of choice).
2. Adjust the scan target (which directories, what file patterns).
3. Adjust the detection logic (what counts as a violation).
4. Write a clear text output: `<rule-name>: N violation(s):` followed by one line per violation, ending with a "Fix:" hint.
5. Implement `--format=json` for machine output.
6. Add to `scripts/verify.sh` under the arch block.
7. Document the new rule in your project's own `docs/architecture-rules.md` (or wherever your team documents conventions).
8. Run on your current codebase. **If it produces violations against existing clean code, the rule is mis-tuned** — either narrow the scope or refactor the existing code first. Shipping a rule that's already broken erodes trust in the whole verify pipeline.

## Why scripts and not just ESLint?

ESLint (and equivalents like Biome) excels at AST-level rules within a single file. Many architecture rules check **cross-file or cross-package** patterns:

- Where does this import resolve to?
- Which feature folder is this file in?
- Does this source file have a matching test next to it?

Those are awkward in ESLint and either require heavier ecosystems (`eslint-plugin-import-x` and family) or custom plugins (more code to maintain).

Single-file scripts are:

- Easier to read and modify (no plugin scaffolding).
- Faster to run for narrow scope.
- Easier for agents to interpret the output of (clean stdout, single concern, structured JSON optional).

Both layers can coexist. Keep AST-level rules in your lint config; keep structural rules as scripts. The verify suite runs both.

When your custom-rule count climbs past ~10 and they start sharing significant logic, revisit. Until then, simple scripts win.
