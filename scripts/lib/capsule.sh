#!/usr/bin/env bash
# capsule.sh — build the handoff capsule for a task from its ledger entries.
# swarm_capsule <ledger> <task> <out-file> <spec-hash>
swarm_capsule() {
  python3 "$SWARM_ROOT/scripts/lib/swarm.py" capsule --ledger "$1" --task "$2" \
    --out "${3:-}" --spec-hash "${4:-}"
}
