#!/usr/bin/env bash
# circuit-breaker.sh — checks the ledger for a task and echoes the verdict.
# Usage: swarm_breaker_check <ledger> <task> <max-runs> <max-handoffs> <max-seconds>
# Prints "OK" or "TRIP <kind> <detail>"; returns 16 on a trip.
swarm_breaker_check() {
  python3 "$SWARM_ROOT/scripts/lib/swarm.py" breaker --ledger "$1" --task "$2" \
    --max-runs "${3:-0}" --max-handoffs "${4:-0}" --max-seconds "${5:-0}"
}
# swarm_claims_check <ledger> <task> <comma-files-or-*>
swarm_claims_check() {
  python3 "$SWARM_ROOT/scripts/lib/swarm.py" claims --ledger "$1" --task "$2" --files "${3:-*}"
}
