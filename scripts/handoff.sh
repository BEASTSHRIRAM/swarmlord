#!/usr/bin/env bash
#
# handoff.sh — hand a WHOLE test-covered task to one agent; on failure, hand
# off to a second agent with a capsule of everything the first one did.
#
#   handoff.sh --dir <repo> --agent <a> [--handoff-to <b>] --tests "<cmd>" "<requirement>"
#
# Protocol: agent A runs with tests as the gate. If A passes, done. If A
# fails, a handoff event is ledgered (the per-task handoff budget applies),
# a capsule is generated, and agent B gets the original requirement + the
# capsule + the instruction to make the tests pass. One handoff by default —
# that is the measured shape of this workflow: small tasks should not be
# handed off at all (see the skill).
set -uo pipefail
SWARM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export SWARM_ROOT
. "$SWARM_ROOT/scripts/lib/common.sh"
. "$SWARM_ROOT/scripts/lib/plugin-options.sh"; load_plugin_options
. "$SWARM_ROOT/scripts/lib/ledger.sh"
. "$SWARM_ROOT/scripts/lib/capsule.sh"

DIR="$PWD"; AGENT_A=""; AGENT_B=""; TESTS=""; TASK_TYPE="default"; PROMPT=""
TASK_ID="handoff-$(date +%Y%m%d%H%M%S)-$$"
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --agent) AGENT_A="$2"; shift 2 ;;
    --handoff-to) AGENT_B="$2"; shift 2 ;;
    --tests) TESTS="$2"; shift 2 ;;
    --task-type) TASK_TYPE="$2"; shift 2 ;;
    --task-id) TASK_ID="$2"; shift 2 ;;
    --) shift; PROMPT="$*"; break ;;
    -*) echo "handoff: unknown option $1" >&2; exit $EX_USAGE ;;
    *) PROMPT="$*"; break ;;
  esac
done
[ -n "$PROMPT" ] || { echo "handoff: a requirement is required" >&2; exit $EX_USAGE; }
DIR="$(cd "$DIR" && pwd)"
LEDGER="$(swarm_ledger_file "$DIR")"
[ -n "$LEDGER" ] || { mkdir -p "$DIR/.swarmlord"; LEDGER="$DIR/.swarmlord/ledger.jsonl"; }
PHASH="$(swarm_prompt_hash "$PROMPT")"

ARGS_A=(--dir "$DIR" --task-type "$TASK_TYPE" --task-id "$TASK_ID" --expect-changes)
[ -n "$AGENT_A" ] && ARGS_A+=(--agent "$AGENT_A")
[ -n "$TESTS" ] && ARGS_A+=(--tests "$TESTS")
bash "$SWARM_ROOT/scripts/delegate.sh" "${ARGS_A[@]}" "$PROMPT"
RC=$?
if [ "$RC" -eq 0 ]; then echo "handoff: first agent completed the task (tests: ${TESTS:-none})" >&2; exit 0; fi
if [ "$RC" -eq $EX_BREAKER ]; then echo "handoff: circuit breaker tripped — stopping, see the conflict report" >&2; exit $RC; fi
[ -n "$AGENT_B" ] || { echo "handoff: first agent failed (rc=$RC) and no --handoff-to agent was given" >&2; exit "$RC"; }

swarm_ledger_append "$LEDGER" "$(swarm_make_entry --task "$TASK_ID" --agent "$AGENT_B" --event handoff --prompt-hash "$PHASH")"
CAPSULE_FILE="$(dirname "$LEDGER")/handoffs/$TASK_ID.md"
CAPSULE="$(swarm_capsule "$LEDGER" "$TASK_ID" "$CAPSULE_FILE" "$PHASH")"
PROMPT2="$PROMPT

--- HANDOFF FROM A PREVIOUS AGENT ---
A previous agent attempted this task and did not finish it cleanly. Its full
state (runs, files changed, test results, errors) is in the capsule below.
Continue from that state; your goal is to complete the task so the tests pass:
${TESTS:-<no test command was provided — verify your work carefully>}

$CAPSULE"
ARGS_B=(--dir "$DIR" --task-type "$TASK_TYPE" --task-id "$TASK_ID" --agent "$AGENT_B" --expect-changes)
[ -n "$TESTS" ] && ARGS_B+=(--tests "$TESTS")
bash "$SWARM_ROOT/scripts/delegate.sh" "${ARGS_B[@]}" "$PROMPT2"
exit $?
