#!/usr/bin/env bash
# adapters/goose.sh — Goose (binary: goose). WARNING: Goose's default permission mode is Autonomous — it can modify files and run tools without approval out of the box. The mode is config-driven (goose configure): Manual Approval / Smart Approval / Chat Only are narrower. TODO: an exact permission-mode flag for `goose run` is not verified, so this adapter passes none — set the mode in goose config before delegating write tasks.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="goose"
a_bin() { echo goose; }
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(goose run --text "$prompt")
  if [ -n "$resume" ]; then CMD+=(--resume-session); fi
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
