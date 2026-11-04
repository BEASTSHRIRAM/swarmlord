#!/usr/bin/env bash
# route.sh — show the routing decision for a task type, with live doctor status.
# Usage: route.sh [--dir <path>] [--task-type <type>]
set -uo pipefail
SWARM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export SWARM_ROOT
. "$SWARM_ROOT/scripts/lib/common.sh"
. "$SWARM_ROOT/scripts/lib/plugin-options.sh"; load_plugin_options
. "$SWARM_ROOT/scripts/lib/router.sh"
. "$SWARM_ROOT/scripts/lib/ledger.sh"
DIR="$PWD"; TASK_TYPE="default"
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --task-type) TASK_TYPE="$2"; shift 2 ;;
    *) TASK_TYPE="$1"; shift ;;
  esac
done
DIR="$(cd "$DIR" && pwd)"
REPO="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || true)"
ROUTING="$(swarm_routing_file "${REPO:-$DIR}")"
LEDGER="$(swarm_ledger_file "$DIR")"
echo "task type: $TASK_TYPE   routing: $ROUTING"
echo "order  agent          status"
i=0
while IFS= read -r cand; do
  [ -n "$cand" ] || continue
  i=$((i+1))
  out="$(bash "$SWARM_ROOT/scripts/adapters/$cand.sh" doctor 2>/dev/null)"; rc=$?
  case "$rc" in 0) st="ready" ;; 11) st="auth failed" ;; *) st="not installed" ;; esac
  printf '%-6s %-14s %s\n' "$i" "$cand" "$st"
done < <(swarm_candidates "$ROUTING" "$TASK_TYPE" "$LEDGER" "")
