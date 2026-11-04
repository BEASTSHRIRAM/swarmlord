#!/usr/bin/env bash
#
# delegate.sh — the single SwarmLord entry point.
#
#   delegate.sh --agent <name> [--dir <path>] [--task-type <type>] "<prompt>"
#   delegate.sh [--task-type <type>] [--dir <path>] "<prompt>"   # routed
#
# Claude Code (the orchestrator) picks an agent explicitly, or the router
# picks from config/routing.json. The chosen CLI runs headlessly in its own
# git worktree/branch; the result is verified against the filesystem (and
# tests, when given); every run is recorded in .git/swarmlord/ledger.jsonl;
# the circuit breaker is checked after every run. Only Claude merges.
#
# Options:
#   --agent <name>        agent id from config/agents.json (else: routed)
#   --dir <path>          repo/working dir (default: cwd)
#   --task-type <type>    frontend|backend|tests|refactor|docs|research|review
#   --task-id <id>        task id for ledger/breaker accounting (default: auto)
#   --model <name>        model override, passed only to adapters that support it
#   --timeout <dur>       per-run wall clock, e.g. 10m (default: routing budgets)
#   --tests "<cmd>"       test command run in the worktree after the agent run
#   --files <a,b>         files this run claims (default: whole worktree "*")
#   --resume <id>         resume a previous agent session where supported
#   --full-trust          pass the agent's full-trust flag (UNSAFE outside a
#                         disposable container; never the default)
#   --no-worktree         run in --dir directly instead of a fresh worktree
#   --expect-changes      treat "agent replied but changed no files" as empty
#   --print-command       print the resolved adapter command and exit
#   -                     read the prompt from stdin
#
# Exit codes: the shared SwarmLord codes (see scripts/lib/common.sh).
# Fallback policy: quota / auth / not-installed fall through to the next
# routed candidate (the failure is ledgered, and quota benches the agent for
# the routing cooldown). Timeout / permission / failed do NOT fall through —
# retrying a different agent would double spend or repeat the same denial.
set -uo pipefail
SWARM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export SWARM_ROOT
. "$SWARM_ROOT/scripts/lib/common.sh"
. "$SWARM_ROOT/scripts/lib/plugin-options.sh"; load_plugin_options
. "$SWARM_ROOT/scripts/lib/router.sh"
. "$SWARM_ROOT/scripts/lib/ledger.sh"
. "$SWARM_ROOT/scripts/lib/circuit-breaker.sh"
. "$SWARM_ROOT/scripts/lib/worktree.sh"
. "$SWARM_ROOT/scripts/lib/capsule.sh"

AGENT=""; DIR="$PWD"; TASK_TYPE="default"; TASK_ID=""; MODEL=""
TIMEOUT=""; TESTS=""; FILES="*"; RESUME=""; FULL_TRUST=0
NO_WORKTREE=0; EXPECT_CHANGES=0; PRINT_CMD=0; PROMPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --task-type) TASK_TYPE="$2"; shift 2 ;;
    --task-id) TASK_ID="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --tests) TESTS="$2"; shift 2 ;;
    --files) FILES="$2"; shift 2 ;;
    --resume) RESUME="$2"; shift 2 ;;
    --full-trust) FULL_TRUST=1; shift ;;
    --no-worktree) NO_WORKTREE=1; shift ;;
    --expect-changes) EXPECT_CHANGES=1; shift ;;
    --print-command) PRINT_CMD=1; shift ;;
    -) PROMPT="$(cat)"; shift ;;
    --) shift; PROMPT="$*"; break ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    -*) echo "delegate: unknown option $1" >&2; exit $EX_USAGE ;;
    *) PROMPT="$*"; break ;;
  esac
done
[ -n "$PROMPT" ] || { echo "delegate: a prompt is required" >&2; exit $EX_USAGE; }
[ -d "$DIR" ] || { echo "delegate: --dir $DIR is not a directory" >&2; exit $EX_USAGE; }
DIR="$(cd "$DIR" && pwd)"
[ -z "$AGENT" ] && AGENT="${CLAUDE_PLUGIN_OPTION_DEFAULT_AGENT:-}"
[ -n "$TASK_ID" ] || TASK_ID="task-$(date +%Y%m%d%H%M%S)-$$"
PROMPT_HASH="$(swarm_prompt_hash "$PROMPT")"

REPO="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || true)"
LEDGER="$(swarm_ledger_file "$DIR")"
if [ -z "$LEDGER" ]; then
  mkdir -p "$DIR/.swarmlord"
  LEDGER="$DIR/.swarmlord/ledger.jsonl"
fi
STATE_DIR="$(dirname "$LEDGER")"
mkdir -p "$STATE_DIR/reports" "$STATE_DIR/handoffs"
ROUTING="$(swarm_routing_file "${REPO:-$DIR}")"
[ -n "$TIMEOUT" ] || TIMEOUT="$(swarm_budget "$ROUTING" per_run_timeout 2>/dev/null || true)"
[ -n "$TIMEOUT" ] || TIMEOUT="${CLAUDE_PLUGIN_OPTION_TIMEOUT:-10m}"
TIMEOUT_SECS="$(swarm_duration_secs "$TIMEOUT")"
MAX_RUNS="$(swarm_budget "$ROUTING" max_runs)"; MAX_HANDOFFS="$(swarm_budget "$ROUTING" max_handoffs)"
MAX_SECONDS="$(swarm_budget "$ROUTING" max_seconds)"

mapfile -t CANDIDATES < <(swarm_candidates "$ROUTING" "$TASK_TYPE" "$LEDGER" "$AGENT")
if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  echo "delegate: no candidate agents for task type '$TASK_TYPE'" >&2; exit $EX_USAGE
fi

if [ "$PRINT_CMD" -eq 1 ]; then
  SWARM_FULL_TRUST=$FULL_TRUST SWARM_RESUME="$RESUME" SWARM_MODEL="$MODEL" \
    bash "$SWARM_ROOT/scripts/adapters/${CANDIDATES[0]}.sh" print-cmd
  exit 0
fi

# --- per-repo run lock (concurrent runs on one repo serialize) ---
LOCKDIR="$STATE_DIR/lock"
_lock_tries=0
while ! mkdir "$LOCKDIR" 2>/dev/null; do
  _lock_tries=$((_lock_tries+1))
  if [ "$_lock_tries" -gt 60 ]; then
    echo "delegate: another SwarmLord run holds the lock for this repo ($LOCKDIR)" >&2
    exit $EX_USAGE
  fi
  sleep 2
done
echo $$ > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR"' EXIT

# --- file claims ---
CLAIM_OUT="$(swarm_claims_check "$LEDGER" "$TASK_ID" "$FILES")"; CLAIM_RC=$?
if [ "$CLAIM_RC" -eq 17 ]; then
  echo "delegate: file-claim conflict — $CLAIM_OUT" >&2; exit $EX_CONFLICT
fi
swarm_ledger_append "$LEDGER" "$(swarm_make_entry --task "$TASK_ID" --event claim --claims "$FILES")"

TMP="$(mktemp -d)"; trap 'rm -rf "$LOCKDIR" "$TMP"' EXIT
LAST_RC=$EX_NOT_INSTALLED

for cand in "${CANDIDATES[@]}"; do
  ADAPTER="$SWARM_ROOT/scripts/adapters/$cand.sh"
  if [ ! -f "$ADAPTER" ]; then
    echo "delegate: no adapter for '$cand', skipping" >&2; LAST_RC=$EX_NOT_INSTALLED; continue
  fi
  # worktree (per candidate, so a fallback agent starts from clean HEAD)
  WT="$DIR"; BRANCH=""
  if [ -n "$REPO" ] && [ "$NO_WORKTREE" -eq 0 ]; then
    WTBR="$(swarm_worktree_create "$REPO" "$TASK_ID" "$cand")" || {
      echo "delegate: could not create worktree for $cand" >&2; LAST_RC=$EX_FAILED; continue; }
    WT="${WTBR%%|*}"; BRANCH="${WTBR##*|}"
  fi
  # doctor gate
  DOC="$(bash "$ADAPTER" doctor 2>/dev/null)"; DOC_RC=$?
  VERSION="$(printf '%s' "$DOC" | sed -n 's/.*version=\([^ ]*\).*/\1/p')"
  if [ "$DOC_RC" -ne 0 ]; then
    CLS="not_installed"; [ "$DOC_RC" -eq 11 ] && CLS="auth"
    swarm_ledger_append "$LEDGER" "$(swarm_make_entry --task "$TASK_ID" --agent "$cand" \
      --event run_end --cls "$CLS" --prompt-hash "$PROMPT_HASH" --version "$VERSION" \
      --model "$MODEL" --worktree "$WT" --branch "$BRANCH")"
    echo "delegate: $cand unavailable ($DOC), trying next" >&2
    LAST_RC="$(swarm_exit_for_class "$CLS")"; continue
  fi
  swarm_snapshot "$WT" > "$TMP/before.txt"
  START="$(date +%s)"
  SWARM_DIR="$WT" SWARM_PROMPT="$PROMPT" SWARM_FULL_TRUST=$FULL_TRUST \
  SWARM_RESUME="$RESUME" SWARM_MODEL="$MODEL" \
    swarm_guard "$TIMEOUT_SECS" bash "$ADAPTER" run > "$TMP/out.txt" 2> "$TMP/err.txt"
  RC=$?
  DUR=$(( $(date +%s) - START ))
  CLS="$(bash "$ADAPTER" classify "$RC" "$TMP/out.txt" "$TMP/err.txt")"
  bash "$ADAPTER" parse "$TMP/out.txt" > "$TMP/reply.txt" 2>>"$TMP/err.txt" || cp "$TMP/out.txt" "$TMP/reply.txt"
  swarm_snapshot "$WT" > "$TMP/after.txt"
  DIFFS="$(python3 "$SWARM_ROOT/scripts/lib/swarm.py" diffsnap --before "$TMP/before.txt" --after "$TMP/after.txt")"
  NCHANGED=0; [ -n "$DIFFS" ] && NCHANGED="$(printf '%s\n' "$DIFFS" | grep -c .)"
  if [ "$CLS" = "ok" ] && [ "$EXPECT_CHANGES" -eq 1 ] && [ "$NCHANGED" -eq 0 ]; then CLS="empty"; fi
  TEST_RESULT=""
  if [ -n "$TESTS" ] && [ "$CLS" = "ok" ]; then
    if ( cd "$WT" && bash -c "$TESTS" ) > "$TMP/tests.txt" 2>&1; then TEST_RESULT="pass"; else TEST_RESULT="fail"; fi
  fi
  SIG=""; [ "$CLS" != "ok" ] && SIG="$(swarm_error_sig "$TMP/err.txt")"
  FILE_ARGS=()
  while IFS='|' read -r fp fb fa; do
    [ -n "$fp" ] && FILE_ARGS+=(--files "$fp|$fb|$fa")
  done <<< "$DIFFS"
  swarm_ledger_append "$LEDGER" "$(swarm_make_entry --task "$TASK_ID" --agent "$cand" \
    --event run_end --cls "$CLS" --error-sig "$SIG" --tests "$TEST_RESULT" \
    --duration "$DUR" --prompt-hash "$PROMPT_HASH" --version "$VERSION" \
    --model "$MODEL" --worktree "$WT" --branch "$BRANCH" "${FILE_ARGS[@]}")"
  # circuit breaker
  VERDICT="$(swarm_breaker_check "$LEDGER" "$TASK_ID" "${MAX_RUNS:-0}" "${MAX_HANDOFFS:-0}" "${MAX_SECONDS:-0}")"; VRC=$?
  if [ "$VRC" -eq 16 ]; then
    if [ -n "$REPO" ] && [ "$NO_WORKTREE" -eq 0 ]; then
      git -C "$WT" add -A >/dev/null 2>&1
      git -C "$WT" commit --allow-empty -m "swarmlord checkpoint: $TASK_ID ($VERDICT)" >/dev/null 2>&1 || true
    fi
    REPORT="$STATE_DIR/reports/$TASK_ID-$(date +%H%M%S).md"
    { echo "# SwarmLord conflict report — task $TASK_ID"; echo; echo "Circuit breaker: $VERDICT"; echo
      swarm_capsule "$LEDGER" "$TASK_ID" "" "$PROMPT_HASH"; } > "$REPORT"
    swarm_ledger_append "$LEDGER" "$(swarm_make_entry --task "$TASK_ID" --agent "$cand" --event trip --cls breaker --error-sig "$VERDICT")"
    cat "$TMP/reply.txt"
    echo "SWARMLORD_RUN {\"task_id\":\"$TASK_ID\",\"agent\":\"$cand\",\"class\":\"breaker\",\"trip\":\"$VERDICT\",\"report\":\"$REPORT\",\"branch\":\"$BRANCH\"}" >&2
    exit $EX_BREAKER
  fi
  cat "$TMP/reply.txt"
  echo "SWARMLORD_RUN {\"task_id\":\"$TASK_ID\",\"agent\":\"$cand\",\"class\":\"$CLS\",\"tests\":\"$TEST_RESULT\",\"files_changed\":$NCHANGED,\"duration_s\":$DUR,\"worktree\":\"$WT\",\"branch\":\"$BRANCH\"}" >&2
  if [ "$CLS" = "ok" ]; then
    [ "$TEST_RESULT" = "fail" ] && exit $EX_FAILED
    exit $EX_OK
  fi
  LAST_RC="$(swarm_exit_for_class "$CLS")"
  case "$CLS" in
    quota|auth|not_installed) echo "delegate: $cand failed ($CLS), trying next candidate" >&2; continue ;;
    *) exit "$LAST_RC" ;;
  esac
done
echo "delegate: all candidates exhausted for task '$TASK_ID'" >&2
exit "$LAST_RC"
