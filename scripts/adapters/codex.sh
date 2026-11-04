#!/usr/bin/env bash
# adapters/codex.sh — OpenAI Codex CLI (binary: codex)
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="codex"
a_bin() { echo codex; }
a_auth_probe() {
  if swarm_guard 15 codex login status >/dev/null 2>&1; then echo ok; else echo bad; fi
}
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(codex exec)
  if [ -n "$resume" ]; then
    CMD+=(resume)
    [ "$resume" != "last" ] && CMD+=("$resume")
    [ "$resume" = "last" ] && CMD+=(--last)
  fi
  if [ "$full" = "1" ]; then CMD+=(--dangerously-bypass-approvals-and-sandbox)
  else CMD+=(--sandbox workspace-write); fi
  [ -n "$model" ] && CMD+=(--model "$model")
  CMD+=("$prompt")
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
