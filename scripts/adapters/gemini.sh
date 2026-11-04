#!/usr/bin/env bash
# adapters/gemini.sh — Gemini CLI (binary: gemini). TODO: no auth-status command in official docs.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="gemini"
a_bin() { echo gemini; }
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(gemini -p "$prompt")
  if [ "$full" = "1" ]; then CMD+=(--approval-mode yolo)
  else CMD+=(--approval-mode auto_edit); fi
  [ -n "$model" ] && CMD+=(--model "$model")
  if [ "${SWARM_STRUCTURED:-0}" = "1" ]; then CMD+=(--output-format json); fi
  if [ -n "$resume" ]; then CMD+=(--resume "$resume"); fi
}
a_parse() {
  if [ "${SWARM_STRUCTURED:-0}" = "1" ] && head -c1 "$1" 2>/dev/null | grep -q '{'; then
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if isinstance(d, dict) and d.get("response"):
        print(d["response"])
        stats = d.get("stats") or {}
        print("SWARMLORD_USAGE gemini stats=%s" % bool(stats), file=sys.stderr)
        sys.exit(0)
except Exception:
    pass
sys.stdout.write(open(sys.argv[1]).read())
' "$1"
  else
    cat "$1"
  fi
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
