#!/usr/bin/env bash
# adapters/muse.sh — Muse Code, Meta (binary: muse). Paid only (no free tier documented). TODO: no auth-status command documented; `muse usage` is the closest probe. JSONL reply-field names are not verified, so this adapter always runs in text mode.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="muse"
a_bin() { echo muse; }
a_auth_probe() {
  if swarm_guard 20 muse usage >/dev/null 2>&1; then echo ok; else echo unknown; fi
}
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(muse exec)
  # Narrow unattended posture: --disable-approval skips approval prompts but
  # KEEPS the OS sandbox on. Full trust (--yolo) disables both — Meta
  # documents it for disposable containers only.
  if [ "$full" = "1" ]; then CMD+=(--yolo); else CMD+=(--disable-approval); fi
  [ -n "$model" ] && CMD+=(--model "$model")
  [ -n "$resume" ] && CMD+=(--session-id "$resume")
  CMD+=("$prompt")
}
a_classify_rc() {
  case "$1" in 2) echo failed ;; *) : ;; esac
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
