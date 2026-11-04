#!/usr/bin/env bash
# adapters/aider.sh — Aider (binary: aider). Git-native pair programmer. TODO: no headless session-resume flag verified — resume is reported unsupported. Note: aider auto-commits its edits by default; inside an SwarmLord worktree those commits land on the run branch, which is where checkpoints also live.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="aider"
a_bin() { echo aider; }
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(aider --message "$prompt")
  # Default: no --yes-always, so confirmations decline on a non-TTY instead
  # of auto-approving. Full trust auto-confirms every prompt.
  [ "$full" = "1" ] && CMD+=(--yes-always)
  [ -n "$model" ] && CMD+=(--model "$model")
  if [ -n "$resume" ]; then
    echo "aider adapter: resume is not supported (TODO) — running fresh" >&2
  fi
}
a_resume_supported() { return 1; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
