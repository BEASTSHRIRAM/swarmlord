#!/usr/bin/env bash
# adapters/kiro.sh — Kiro CLI (binary: kiro-cli). Headless requires KIRO_API_KEY.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="kiro"
a_bin() { echo kiro-cli; }
a_auth_probe() {
  if swarm_guard 15 kiro-cli whoami >/dev/null 2>&1; then echo ok; else echo bad; fi
}
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(kiro-cli chat --no-interactive)
  if [ "$full" = "1" ]; then CMD+=(--trust-all-tools)
  elif [ -n "${SWARM_TRUST_TOOLS:-}" ]; then CMD+=(--trust-tools="$SWARM_TRUST_TOOLS"); fi
  # Narrow default: no trust flags — untrusted tool calls are denied in
  # non-interactive mode. Set SWARM_TRUST_TOOLS=<tool IDs> for a scoped grant.
  if [ -n "$resume" ]; then
    if [ "$resume" = "last" ]; then CMD+=(--resume); else CMD+=(--resume-id "$resume"); fi
  fi
  CMD+=("$prompt")
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
