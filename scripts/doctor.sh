#!/usr/bin/env bash
# doctor.sh — health check across every SwarmLord adapter + plugin wiring.
set -uo pipefail
SWARM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export SWARM_ROOT
. "$SWARM_ROOT/scripts/lib/plugin-options.sh"; load_plugin_options
FAIL=0; HEALTHY=0
echo "SwarmLord — doctor"
echo ""
echo "Agents:"
for a in "$SWARM_ROOT"/scripts/adapters/*.sh; do
  name="$(basename "$a" .sh)"
  [ "$name" = "_template" ] && continue
  out="$(bash "$a" doctor 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then st="ready"; HEALTHY=$((HEALTHY+1));
  elif [ "$rc" -eq 11 ]; then st="AUTH FAILED"; FAIL=1;
  else st="not installed"; fi
  printf '  %-14s %-14s %s\n' "$name" "$st" "$out"
done
echo ""
echo "Plugin wiring:"
for f in config/agents.json config/routing.json .claude-plugin/plugin.json; do
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SWARM_ROOT/$f" 2>/dev/null; then
    echo "  ✓ $f parses"
  else echo "  ✗ $f missing or invalid JSON"; FAIL=1; fi
done
for s in scripts/delegate.sh scripts/handoff.sh scripts/job.sh scripts/doctor.sh; do
  [ -x "$SWARM_ROOT/$s" ] && echo "  ✓ $s executable" || { echo "  ✗ $s not executable"; FAIL=1; }
done
for b in "$SWARM_ROOT"/bin/*; do
  [ -x "$b" ] || { echo "  ✗ bin/$(basename "$b") not executable"; FAIL=1; }
done
echo ""
if [ "$HEALTHY" -eq 0 ]; then echo "No agent is ready — install/authenticate at least one CLI (see config/agents.json)."; FAIL=1; fi
[ "$FAIL" -eq 0 ] && echo "Ready: $HEALTHY agent(s) available." || echo "Some checks failed — see above."
exit "$FAIL"
