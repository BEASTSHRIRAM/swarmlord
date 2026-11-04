#!/usr/bin/env bash
# adapters/antigravity.sh — Antigravity CLI (binary: agy). Behaviour carried over from the upstream wrapper, verified against agy 1.1.8-1.4.4: print mode needs stdin from /dev/null (the base run does this), --model is honoured headless only from 1.1.10, JSON output from 1.1.8.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="antigravity"
a_bin() { echo agy; }
a_auth_probe() {
  local out rc
  out="$(swarm_guard 20 agy models 2>/dev/null)"; rc=$?
  if [ -n "$out" ]; then echo ok
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then echo unknown  # a hang is not an auth failure
  else echo bad; fi
}
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=(agy -p "$prompt" --add-dir "${SWARM_DIR:-.}")
  [ "$full" = "1" ] && CMD+=(--dangerously-skip-permissions)
  [ -n "$model" ] && CMD+=(--model "$model")
  if [ "${SWARM_STRUCTURED:-0}" = "1" ]; then CMD+=(--output-format json); fi
  if [ -n "$resume" ]; then
    if [ "$resume" = "last" ]; then CMD+=(-c); else CMD+=(--conversation "$resume"); fi
  fi
}
a_parse() {
  if [ "${SWARM_STRUCTURED:-0}" = "1" ] && head -c1 "$1" 2>/dev/null | grep -q '{'; then
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if isinstance(d, dict):
        for k in ("response", "text", "result", "finalText"):
            if d.get(k):
                print(d[k]); sys.exit(0)
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
