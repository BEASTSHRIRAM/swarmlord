#!/usr/bin/env bash
# SessionStart hook: fast, network-free check that at least one delegated
# agent CLI is on PATH. Warns on stderr but NEVER fails the session.
set -uo pipefail
found=""
for b in codex kiro-cli copilot gemini opencode cmd command-code muse agy aider goose; do
  if command -v "$b" >/dev/null 2>&1; then found="$found $b"; fi
done
if [ -z "$found" ]; then
  echo "[swarmlord] no agent CLI found on PATH — delegation is unavailable until you install one (see config/agents.json) or configure the local adapter." >&2
else
  echo "[swarmlord] agent CLIs on PATH:$found" >&2
fi
exit 0
