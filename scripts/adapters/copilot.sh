#!/usr/bin/env bash
# adapters/copilot.sh — GitHub Copilot CLI (binary: copilot). TODO: no auth-status command in official docs; --model not verified, never passed.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="copilot"
a_bin() { echo copilot; }
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(copilot -p "$prompt" -s --no-ask-user)
  if [ "$full" = "1" ]; then
    CMD+=(--allow-all)
  elif [ -n "${SWARM_COPILOT_ALLOW:-}" ]; then
    local IFS=','; local t
    for t in $SWARM_COPILOT_ALLOW; do CMD+=(--allow-tool="$t"); done
    unset IFS
  else
    # Narrow default grant: file writes + shell, the two kinds a coding
    # delegation needs. Tighten or widen with SWARM_COPILOT_ALLOW=a,b,c.
    CMD+=(--allow-tool=write --allow-tool=shell)
  fi
  if [ -n "$resume" ]; then
    if [ "$resume" = "last" ]; then CMD+=(--continue); else CMD+=(--resume="$resume"); fi
  fi
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
