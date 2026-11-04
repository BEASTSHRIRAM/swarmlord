#!/usr/bin/env bash
# SessionStart hook: inject the SwarmLord routing policy as session context.
# Toggle via plugin userConfig `coding_policy` (CLAUDE_PLUGIN_OPTION_CODING_POLICY).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
raw="$(printf '%s' "${CLAUDE_PLUGIN_OPTION_CODING_POLICY:-on}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$raw" in off|false|0|no|disabled) exit 0 ;; esac
cat "$HERE/policy-context.json"
exit 0
