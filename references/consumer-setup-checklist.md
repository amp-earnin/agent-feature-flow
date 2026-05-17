# Consumer setup checklist

After installing the feature-flow plugin, a host repo must wire up a small amount of project-side glue. This checklist walks through it. Most steps are quick; only step 4 (reviewer agents) takes meaningful work.

## 1. Install required MCP servers

The `gather-requirements` skill pulls data from external sources via MCP. The workflow gracefully degrades when any source is missing, but the **ticket source is required** — without it, the workflow has no entrypoint.

| Source                 | MCP server (common name)                                         | Required? |
| ---------------------- | ---------------------------------------------------------------- | --------- |
| JIRA (or your tracker) | `atlassian-rovo` (or equivalent for Linear, GitHub Issues, etc.) | **Yes**   |
| Figma designs          | `figma`                                                          | Optional  |
| Confluence pages       | covered by Atlassian Rovo                                        | Optional  |
| Slack threads          | `slack`                                                          | Optional  |
| Google Docs            | `glean` or `google-drive`                                        | Optional  |

See your Claude Code configuration (`/mcp` or `claude mcp ...`) to install and authenticate each.

## 2. Set up `scripts/verify.sh` in your repo

Copy `${CLAUDE_PLUGIN_ROOT}/references/recipes/verify.sh.example` to `scripts/verify.sh` in your project. Edit the check list to match your stack:

```bash
mkdir -p scripts
cp "${CLAUDE_PLUGIN_ROOT}/references/recipes/verify.sh.example" scripts/verify.sh
chmod +x scripts/verify.sh
$EDITOR scripts/verify.sh  # tune the run "X" commands to your stack
```

Smoke-test:

```bash
bash scripts/verify.sh
```

The `verify-architecture` skill contracts on this script. See its SKILL.md for the contract.

## 3. (Optional) Wire the PostEdit hook

For tight feedback during implementation, wire a PostToolUse hook that runs `verify.sh --quick` on every edit.

1. Copy the example to your repo:

   ```bash
   cp "${CLAUDE_PLUGIN_ROOT}/hooks/post-edit-verify.sh.example" scripts/hook-post-edit.sh
   chmod +x scripts/hook-post-edit.sh
   ```

   Edit the exclusion list at the bottom — add any project directories whose edits should NOT trigger verify (e.g. docs, build outputs, generated code).

2. Add to your project's `.claude/settings.json`:

   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "Edit|Write|NotebookEdit",
           "hooks": [
             { "type": "command", "command": "bash scripts/hook-post-edit.sh", "timeout": 30 }
           ]
         }
       ]
     }
   }
   ```

This step is consumer-side because the hook's exclusion list and the verify.sh location are project-specific.

## 4. Override the reviewer agents (recommended)

The plugin ships two reviewer-team agents as **skeletons**:

- `architecture-reviewer`
- `frontend-ux-reviewer`

They describe the _categories_ a reviewer should attend to, but the specifics depend on your codebase. Without a project-scoped override, reviewers will produce generic comments.

For each, create a project-scoped override at `.claude/agents/<name>.md` filled with your project's specifics:

1. Copy the plugin's `agents/<name>.md` to your repo's `.claude/agents/<name>.md`.
2. Replace each customization section ("Document your codebase's…") with your codebase's actual conventions.
3. The reference `<!-- EXAMPLE -->` blocks at the bottom of the plugin agents show what a fully-populated reviewer looks like for a particular stack. Copy those into your override if your stack overlaps.

Claude Code resolves project-scoped agents over plugin-scoped ones with the same name, so the override happens transparently.

## 5. (Optional) Author project-specific architecture rules

If your project has structural patterns worth enforcing (e.g., no cross-feature imports, no raw fetch outside your data layer), add scripts under `scripts/arch/` and hook them into your `scripts/verify.sh`. Three working examples ship at `${CLAUDE_PLUGIN_ROOT}/skills/verify-architecture/references/arch-rule-examples/`. Each has a "WHAT TO CUSTOMIZE" header showing exactly what to change.

## 6. Ignore workflow state in git

Add to your `.gitignore`:

```
.claude/features/
```

Workflow state for each feature run lives at `.claude/features/<TICKET>/state.json`. It's ephemeral and per-developer; don't commit it.

## 7. (Optional) Set the ticket-ID pattern

If your tracker uses a regex other than `^[A-Z]+-\d+$` (the JIRA-style default), edit your project's `.claude/commands/feature.md` to match. The slash command validates `$ARGUMENTS` against this pattern before doing anything.

---

When steps 1–7 are done, run `/feature <TICKET>` on a real ticket as the end-to-end smoke test. The workflow should reach **Checkpoint 1** (brief approval) without errors. From there, approve and let it run; review the PR it eventually opens.
