#!/usr/bin/env bash
# adapters/opencode.sh — OpenCode (binary: opencode). Permissions are config-driven; no --yolo flag is documented — run --auto is the closest full-trust equivalent and still honours explicit deny rules.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="opencode"
a_bin() { echo opencode; }
a_auth_probe() {
  local out
  out="$(swarm_guard 15 opencode auth list 2>/dev/null)"
  if [ -n "$out" ]; then echo ok; else echo unknown; fi
}
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(opencode run)
  [ "$full" = "1" ] && CMD+=(--auto)
  [ -n "$model" ] && CMD+=(--model "$model")
  if [ -n "$resume" ]; then
    if [ "$resume" = "last" ]; then CMD+=(--continue); else CMD+=(--session "$resume"); fi
  fi
  CMD+=("$prompt")
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
