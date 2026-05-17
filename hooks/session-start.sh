#!/usr/bin/env bash
# SessionStart hook for the feature-flow plugin.
# Emits a one-line nudge so users see the plugin is loaded and know how to use it.

cat <<'EOF'
{
  "priority": "IMPORTANT",
  "message": "feature-flow plugin loaded. Start an end-to-end feature workflow with /feature <TICKET-ID>. See the using-feature-flow skill for the decision tree, or skills/feature-flow-conductor for the full process."
}
EOF
