#!/usr/bin/env bash
# router.sh — resolve the ordered candidate list for a task.
# Resolution order for routing.json: $SWARMLORD_ROUTING > <repo>/.swarmlord/routing.json
# > <plugin>/config/routing.json (shipped defaults).
swarm_routing_file() {
  local repo="$1"
  if [ -n "${SWARMLORD_ROUTING:-}" ] && [ -f "${SWARMLORD_ROUTING:-}" ]; then echo "$SWARMLORD_ROUTING"; return; fi
  if [ -n "$repo" ] && [ -f "$repo/.swarmlord/routing.json" ]; then echo "$repo/.swarmlord/routing.json"; return; fi
  echo "$SWARM_ROOT/config/routing.json"
}
# swarm_candidates <routing-file> <task-type> <ledger-file> [requested-agent]
swarm_candidates() {
  python3 "$SWARM_ROOT/scripts/lib/swarm.py" route --routing "$1" --task-type "$2" \
    --ledger "${3:-}" --agent "${4:-}"
}
# swarm_budget <routing-file> <key> — read budgets.per_task.<key> (empty if unset/null)
swarm_budget() {
  python3 -c '
import json, sys
try:
    r = json.load(open(sys.argv[1]))
    v = ((r.get("budgets") or {}).get("per_task") or {}).get(sys.argv[2])
except Exception:
    v = None
print("" if v is None else v)
' "$1" "$2"
}
