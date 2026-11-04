#!/usr/bin/env bash
#
# job.sh — background delegation jobs (interactive sessions: fire & collect).
#   job.sh start <delegate.sh args...>   start a job, print its id
#   job.sh status [id]                   list jobs or show one
#   job.sh result <id>                   print a finished job's reply
#   job.sh cancel <id>                   stop a running job
# In headless one-shot runs, delegate synchronously instead — there is no
# later turn to collect a background result.
set -uo pipefail
SWARM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export SWARM_ROOT
. "$SWARM_ROOT/scripts/lib/ledger.sh"
LEDGER="$(swarm_ledger_file "$PWD")"
if [ -n "$LEDGER" ]; then JOBDIR="$(dirname "$LEDGER")/jobs"; else JOBDIR="$PWD/.swarmlord/jobs"; fi
mkdir -p "$JOBDIR"
cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  start)
    id="job-$(date +%Y%m%d%H%M%S)-$$"
    mkdir -p "$JOBDIR/$id"
    printf '%q ' "$@" > "$JOBDIR/$id/args"
    ( bash "$SWARM_ROOT/scripts/delegate.sh" "$@" > "$JOBDIR/$id/out" 2> "$JOBDIR/$id/err"; echo $? > "$JOBDIR/$id/rc" ) &
    echo $! > "$JOBDIR/$id/pid"
    echo "$id" ;;
  status)
    if [ -n "${1:-}" ]; then ids=("$1"); else ids=(); for d in "$JOBDIR"/*/; do [ -d "$d" ] && ids+=("$(basename "$d")"); done; fi
    for id in "${ids[@]}"; do
      [ -d "$JOBDIR/$id" ] || { echo "$id: unknown"; continue; }
      if [ -f "$JOBDIR/$id/rc" ]; then echo "$id: done rc=$(cat "$JOBDIR/$id/rc")";
      elif kill -0 "$(cat "$JOBDIR/$id/pid" 2>/dev/null)" 2>/dev/null; then echo "$id: running";
      else echo "$id: stopped (no rc recorded)"; fi
    done ;;
  result)
    id="${1:?result needs a job id}"
    cat "$JOBDIR/$id/out" 2>/dev/null
    if [ ! -f "$JOBDIR/$id/rc" ]; then echo "job $id has not finished" >&2; exit 1; fi ;;
  cancel)
    id="${1:?cancel needs a job id}"
    pid="$(cat "$JOBDIR/$id/pid" 2>/dev/null || true)"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    echo "cancelled $id" ;;
  *) echo "usage: job.sh start|status|result|cancel ..." >&2; exit 1 ;;
esac
