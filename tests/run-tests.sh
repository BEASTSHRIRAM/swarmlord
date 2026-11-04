#!/usr/bin/env bash
#
# run-tests.sh — stub-based tests for SwarmLord. No real agent CLI is needed:
# tests/stubs/bin holds a generic fake for every agent binary, and a stub
# HTTP server stands in for the local LLM endpoint.
#
#   bash tests/run-tests.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null' EXIT
export CLAUDE_CONFIG_DIR="$TMP/claude-config"   # isolate plugin options
STUBBIN="$HERE/stubs/bin"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok: $*"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $*"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$3] got [$2])"; fi }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing [$3] in output)" ;; esac }

# ---------- static checks ----------
python3 -c 'import json; [json.load(open(f)) for f in ["config/agents.json","config/routing.json",".claude-plugin/plugin.json",".claude-plugin/marketplace.json","hooks/hooks.json"]]' 2>/dev/null \
  && ok "all shipped JSON parses" || bad "all shipped JSON parses"
( cd "$ROOT" && python3 -c '
import json
a = json.load(open("config/agents.json"))["agents"]
assert len(a) == 11, len(a)
r = json.load(open("config/routing.json"))["task_types"]
assert set(r) >= {"frontend","backend","tests","refactor","docs","research","review","default"}
print("ok")' ) >/dev/null 2>&1 && ok "agents.json has 11 agents; routing has all task types" || bad "manifest shape"
for f in scripts/lib/plugin-options.sh scripts/lib/router.sh scripts/adapters/gemini.sh scripts/adapters/antigravity.sh scripts/adapters/local.sh; do
  python3 "$HERE/check-embedded-python.py" "$ROOT/$f" >/dev/null 2>&1 \
    && ok "embedded python intact: $f" || bad "embedded python intact: $f"
done
grep -rq "agy-delegate\|agy-job\|agy-handoff" "$ROOT/scripts" "$ROOT/bin" "$ROOT/commands" "$ROOT/hooks" "$ROOT/.claude-plugin" 2>/dev/null \
  && bad "no upstream agy-* wrapper names remain" || ok "no upstream agy-* wrapper names remain"
[ "$(python3 -c 'import json; print(json.load(open("'"$ROOT"'/.claude-plugin/plugin.json"))["name"])')" = "swarmlord" ] \
  && ok "plugin renamed to swarmlord" || bad "plugin renamed to swarmlord"

# ---------- adapter interface (stub CLIs) ----------
export PATH="$STUBBIN:$PATH"
ADAPTERS="codex kiro copilot gemini opencode command-code muse antigravity aider goose"
for a in $ADAPTERS; do
  ad="$ROOT/scripts/adapters/$a.sh"
  out="$(bash "$ad" doctor 2>/dev/null)"; rc=$?
  check "adapter $a doctor rc" "$rc" "0"
  has "adapter $a doctor line" "$out" "agent=$a"
  out="$(bash "$ad" print-cmd 2>/dev/null)"; has "adapter $a print-cmd" "$out" "<prompt>"
  out="$(SWARM_DIR="$TMP" SWARM_PROMPT="do the thing" bash "$ad" run 2>/dev/null)"; rc=$?
  check "adapter $a run rc" "$rc" "0"
  has "adapter $a run reply" "$out" "stub reply"
  for mode in quota auth permission empty; do
    STUB_MODE=$mode SWARM_DIR="$TMP" SWARM_PROMPT="x" bash "$ad" run > "$TMP/o.txt" 2> "$TMP/e.txt"; rrc=$?
    cls="$(bash "$ad" classify "$rrc" "$TMP/o.txt" "$TMP/e.txt")"
    check "adapter $a classify $mode" "$cls" "$mode"
  done
done
# command-code documented exit-code mapping wins over text patterns
STUB_RC=3 SWARM_DIR="$TMP" SWARM_PROMPT="x" bash "$ROOT/scripts/adapters/command-code.sh" run > "$TMP/o.txt" 2> "$TMP/e.txt"; rrc=$?
check "command-code rc3 -> auth" "$(bash "$ROOT/scripts/adapters/command-code.sh" classify "$rrc" "$TMP/o.txt" "$TMP/e.txt")" "auth"
STUB_RC=10 SWARM_DIR="$TMP" SWARM_PROMPT="x" bash "$ROOT/scripts/adapters/command-code.sh" run > "$TMP/o.txt" 2> "$TMP/e.txt"; rrc=$?
check "command-code rc10 -> quota" "$(bash "$ROOT/scripts/adapters/command-code.sh" classify "$rrc" "$TMP/o.txt" "$TMP/e.txt")" "quota"
# resume support flags
bash "$ROOT/scripts/adapters/codex.sh" resume-supported && ok "codex resume supported" || bad "codex resume supported"
bash "$ROOT/scripts/adapters/aider.sh" resume-supported && bad "aider resume unsupported" || ok "aider resume unsupported"
# full-trust is opt-in only
out="$(bash "$ROOT/scripts/adapters/codex.sh" print-cmd)"
case "$out" in *dangerously-bypass*) bad "codex default has no full-trust flag" ;; *) ok "codex default has no full-trust flag" ;; esac
out="$(SWARM_FULL_TRUST=1 bash "$ROOT/scripts/adapters/codex.sh" print-cmd)"
has "codex full-trust opt-in" "$out" "dangerously-bypass"
# doctor with the binary missing
out="$(PATH=/usr/bin:/bin bash "$ROOT/scripts/adapters/gemini.sh" doctor 2>/dev/null)"; rc=$?
if command -v gemini >/dev/null 2>&1 && [ "${PATH}" != "/usr/bin:/bin" ]; then :; fi
if [ "$rc" = "15" ] || [ "$rc" = "0" ]; then ok "gemini doctor handles missing binary (rc=$rc)"; else bad "gemini doctor handles missing binary (rc=$rc)"; fi

# ---------- local adapter (stub HTTP endpoint) ----------
export STUB_LOCAL_PORT=18711
python3 "$HERE/stubs/local-server.py" & SERVER_PID=$!
sleep 1
export SWARMLORD_LOCAL_URL="http://127.0.0.1:18711" SWARMLORD_LOCAL_MODEL="stub-model"
out="$(bash "$ROOT/scripts/adapters/local.sh" doctor 2>/dev/null)"; rc=$?
check "local doctor rc" "$rc" "0"
out="$(SWARM_DIR="$TMP" SWARM_PROMPT="hello" bash "$ROOT/scripts/adapters/local.sh" run 2>/dev/null)"
has "local run reply" "$out" "local stub reply"
kill "$SERVER_PID" 2>/dev/null; SERVER_PID=""
out="$(bash "$ROOT/scripts/adapters/local.sh" doctor 2>/dev/null)"; rc=$?
check "local doctor with endpoint down -> 15" "$rc" "15"
unset SWARMLORD_LOCAL_URL SWARMLORD_LOCAL_MODEL

# ---------- router ----------
SWARMPY="$ROOT/scripts/lib/swarm.py"
led="$TMP/ledger.jsonl"; : > "$led"
first="$(python3 "$SWARMPY" route --routing "$ROOT/config/routing.json" --task-type frontend --ledger "$led" | head -1)"
check "router frontend first choice" "$first" "gemini"
python3 "$SWARMPY" append --ledger "$led" --entry "{\"ts\": $(date +%s), \"task_id\": \"t0\", \"agent\": \"gemini\", \"event\": \"run_end\", \"class\": \"quota\"}"
first="$(python3 "$SWARMPY" route --routing "$ROOT/config/routing.json" --task-type frontend --ledger "$led" | head -1)"
check "router skips quota-cooldowned agent" "$first" "codex"
first="$(python3 "$SWARMPY" route --routing "$ROOT/config/routing.json" --task-type frontend --ledger "$led" --agent muse)"
check "router honours explicit agent" "$first" "muse"

# ---------- circuit breaker (unit) ----------
mkled() { # $1 = file; rest = entries via python
  python3 - "$1" <<'PYEOF'
import json, sys
path = sys.argv[1]
def run(agent, cls, sig, files, ev="run_end"):
    return {"ts": 1000, "task_id": "T", "agent": agent, "event": ev, "class": cls,
            "error_sig": sig, "tests": "", "duration_s": 1, "files": files}
rows = {
 "recurrence": [run("codex","ok","",{"f.txt":{"before":"h0","after":"h1"}}),
                run("codex","ok","",{"f.txt":{"before":"h1","after":"h0"}})],
 "cross":      [run("codex","ok","",{"f.txt":{"before":"h0","after":"h1"}}),
                run("gemini","ok","",{"f.txt":{"before":"h1","after":"h0"}})],
 "reperr":     [run("codex","quota","sig:X x",{}), run("codex","quota","sig:X x",{})],
 "healthy":    [run("codex","ok","",{"f.txt":{"before":"h0","after":"h1"}}),
                run("gemini","ok","",{"g.txt":{"before":"h0","after":"h2"}})],
}
import os
name = os.path.basename(path).replace(".jsonl","")
with open(path, "w") as f:
    for r in rows[name]:
        f.write(json.dumps(r) + "\n")
PYEOF
}
for case in recurrence cross reperr healthy; do
  mkled "$TMP/$case.jsonl"
  out="$(python3 "$SWARMPY" breaker --ledger "$TMP/$case.jsonl" --task T --max-runs 8 --max-handoffs 3 --max-seconds 3600)"; rc=$?
  case "$case" in
    recurrence) has "breaker recurrence" "$out" "TRIP state_recurrence"; check "breaker recurrence rc" "$rc" "16" ;;
    cross) has "breaker cross-agent revert" "$out" "TRIP cross_agent_revert" ;;
    reperr) has "breaker repeated error" "$out" "TRIP repeated_error" ;;
    healthy) check "breaker healthy" "$out" "OK" ;;
  esac
done
mkled "$TMP/healthy.jsonl"
out="$(python3 "$SWARMPY" breaker --ledger "$TMP/healthy.jsonl" --task T --max-runs 1 --max-handoffs 3 --max-seconds 3600)"
has "breaker budget runs" "$out" "TRIP budget_runs"

# ---------- claims ----------
led2="$TMP/claims.jsonl"; : > "$led2"
python3 "$SWARMPY" append --ledger "$led2" --entry "{\"ts\": $(date +%s), \"task_id\": \"other\", \"agent\": \"\", \"event\": \"claim\", \"claims\": [\"a.txt\"]}"
out="$(python3 "$SWARMPY" claims --ledger "$led2" --task mine --files a.txt)"; rc=$?
check "claim conflict rc" "$rc" "17"
python3 "$SWARMPY" append --ledger "$led2" --entry "{\"ts\": $(date +%s), \"task_id\": \"other\", \"agent\": \"codex\", \"event\": \"run_end\", \"class\": \"ok\"}"
out="$(python3 "$SWARMPY" claims --ledger "$led2" --task mine --files a.txt)"; rc=$?
check "claim released after run_end" "$rc" "0"

# ---------- delegate end-to-end (temp git repo, stubs) ----------
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t.t; git -C "$REPO" config user.name t
printf 'original\n' > "$REPO/file.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -qm init
DEL="$ROOT/scripts/delegate.sh"
out="$(STUB_WRITE=file.txt STUB_CONTENT=v2 bash "$DEL" --task-type backend --dir "$REPO" --task-id e2e1 --tests "grep -q v2 file.txt" "change file" 2>"$TMP/err.txt")"; rc=$?
check "delegate routed run rc" "$rc" "0"
has "delegate reply" "$out" "stub reply"
has "delegate summary" "$(cat "$TMP/err.txt")" "SWARMLORD_RUN"
grep -q '"class": "ok"' "$REPO/.git/swarmlord/ledger.jsonl" && ok "ledger recorded ok run" || bad "ledger recorded ok run"
grep -q '"tests": "pass"' "$REPO/.git/swarmlord/ledger.jsonl" && ok "ledger recorded test pass" || bad "ledger recorded test pass"
git -C "$REPO" branch --list "swarmlord/e2e1-codex" | grep -q swarmlord && ok "run branch created" || bad "run branch created"
# no prompt text in the ledger (hashes only)
grep -q "change file" "$REPO/.git/swarmlord/ledger.jsonl" && bad "ledger stores no prompt text" || ok "ledger stores no prompt text"
# fallback: gemini quota -> codex succeeds (frontend routes gemini first)
out="$(STUB_MODE_GEMINI=quota STUB_WRITE=file.txt STUB_CONTENT=v3 bash "$DEL" --task-type frontend --dir "$REPO" --task-id e2e2 "change file" 2>/dev/null)"; rc=$?
check "delegate fallback rc" "$rc" "0"
grep -q '"agent": "gemini".*"class": "quota"' "$REPO/.git/swarmlord/ledger.jsonl" && ok "fallback ledgered quota" || bad "fallback ledgered quota"
# expect-changes gate: reply but no file change -> empty (3)
out="$(bash "$DEL" --agent codex --dir "$REPO" --task-id e2e3 --expect-changes "talk only" 2>/dev/null)"; rc=$?
check "expect-changes with no changes -> 3" "$rc" "3"
# circuit breaker e2e: agent returns file.txt to its original hash
STUB_WRITE=file.txt STUB_CONTENT=v9 bash "$DEL" --agent codex --dir "$REPO" --task-id trip1 "v9" >/dev/null 2>&1
out="$(STUB_WRITE=file.txt STUB_CONTENT=original bash "$DEL" --agent codex --dir "$REPO" --task-id trip1 "revert" 2>"$TMP/err.txt")"; rc=$?
check "breaker trip exit code" "$rc" "16"
ls "$REPO/.git/swarmlord/reports/"*trip1* >/dev/null 2>&1 && ok "conflict report written" || bad "conflict report written"
# PreToolUse hook blocks the tripped task
hookout="$(printf '{"tool_input":{"command":"swarmlord-delegate --task-id trip1 \\"again\\""},"cwd":"%s"}' "$REPO" | bash "$ROOT/hooks/circuit-breaker.sh" 2>&1)"; rc=$?
check "PreToolUse hook blocks tripped task" "$rc" "2"
# claim conflict e2e
python3 "$SWARMPY" append --ledger "$REPO/.git/swarmlord/ledger.jsonl" --entry "{\"ts\": $(date +%s), \"task_id\": \"holder\", \"agent\": \"\", \"event\": \"claim\", \"claims\": [\"file.txt\"]}"
out="$(bash "$DEL" --agent codex --dir "$REPO" --task-id other1 --files file.txt "x" 2>/dev/null)"; rc=$?
check "delegate claim conflict -> 17" "$rc" "17"
python3 "$SWARMPY" append --ledger "$REPO/.git/swarmlord/ledger.jsonl" --entry "{\"ts\": $(date +%s), \"task_id\": \"holder\", \"agent\": \"codex\", \"event\": \"run_end\", \"class\": \"ok\"}"

# ---------- handoff end-to-end ----------
REPO2="$TMP/repo2"; mkdir -p "$REPO2"
git -C "$REPO2" init -q -b main; git -C "$REPO2" config user.email t@t.t; git -C "$REPO2" config user.name t
printf 'original\n' > "$REPO2/file.txt"; git -C "$REPO2" add -A; git -C "$REPO2" commit -qm init
out="$(STUB_MODE_CODEX=fail STUB_WRITE=file.txt STUB_CONTENT=done bash "$ROOT/scripts/handoff.sh" --dir "$REPO2" --agent codex --handoff-to gemini --task-id ho1 --tests "grep -q done file.txt" "finish the task" 2>"$TMP/err.txt")"; rc=$?
check "handoff rc (B completes)" "$rc" "0"
grep -q '"event": "handoff"' "$REPO2/.git/swarmlord/ledger.jsonl" && ok "handoff ledgered" || bad "handoff ledgered"
[ -f "$REPO2/.git/swarmlord/handoffs/ho1.md" ] && ok "capsule written" || bad "capsule written"
grep -q "Agents so far" "$REPO2/.git/swarmlord/handoffs/ho1.md" 2>/dev/null && ok "capsule has content" || bad "capsule has content"

# ---------- background job ----------
JOBID="$(cd "$REPO" && STUB_WRITE=file.txt STUB_CONTENT=v7 bash "$ROOT/scripts/job.sh" start --agent codex --dir "$REPO" --task-id job1 "bg task")"
for i in $(seq 1 30); do
  st="$(cd "$REPO" && bash "$ROOT/scripts/job.sh" status "$JOBID")"
  case "$st" in *done*) break ;; esac
  sleep 0.5
done
has "job finishes" "$st" "done"
out="$(cd "$REPO" && bash "$ROOT/scripts/job.sh" result "$JOBID" 2>/dev/null)"
has "job result reply" "$out" "stub reply"

# ---------- doctor ----------
out="$(bash "$ROOT/scripts/doctor.sh" 2>/dev/null)"; rc=$?
check "doctor rc with stubs" "$rc" "0"
has "doctor reports agents" "$out" "codex"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
