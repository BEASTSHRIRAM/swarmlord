#!/usr/bin/env bash
#
# PreToolUse(Bash) circuit-breaker gate for SwarmLord delegations.
#
# If a Bash command invokes the delegation wrapper for a task whose ledger
# already carries an UNRESOLVED circuit-breaker trip, block it (exit 2) —
# the user must decide before that task burns more runs. Any other command,
# and any delegation for a healthy task, passes untouched (exit 0, silent).
# Fails OPEN on unparseable input by design: this gate guards a specific
# known-bad state, it is not a general command firewall (that is
# validate-delegate-bash.sh's job, scoped to the delegate subagent).
set -uo pipefail
input="$(cat)"
SWARM_HOOK_INPUT="$input" python3 - <<'PY'
import json, os, re, subprocess, sys

try:
    payload = json.loads(os.environ.get("SWARM_HOOK_INPUT", ""))
    cmd = payload.get("tool_input", {}).get("command", "")
    cwd = payload.get("cwd") or os.getcwd()
except Exception:
    sys.exit(0)
if not isinstance(cmd, str):
    sys.exit(0)
first = cmd.strip().split(None, 1)[0] if cmd.strip() else ""
base = os.path.basename(first).removesuffix(".sh")
if base not in ("swarmlord-delegate", "delegate", "swarmlord-handoff", "handoff"):
    sys.exit(0)
m = re.search(r"--task-id[= ]([A-Za-z0-9._-]+)", cmd)
if not m:
    sys.exit(0)  # a fresh auto-id task cannot have a trip yet
task = m.group(1)
try:
    gd = subprocess.run(["git", "-C", cwd, "rev-parse", "--git-dir"],
                        capture_output=True, text=True, timeout=5).stdout.strip()
    if not gd:
        sys.exit(0)
    if not os.path.isabs(gd):
        gd = os.path.join(cwd, gd)
except Exception:
    sys.exit(0)
ledger = os.path.join(gd, "swarmlord", "ledger.jsonl")
if not os.path.exists(ledger):
    sys.exit(0)
tripped = False
for line in open(ledger, encoding="utf-8", errors="replace"):
    try:
        row = json.loads(line)
    except Exception:
        continue
    if row.get("task_id") != task:
        continue
    if row.get("event") == "trip":
        tripped = True
    elif row.get("event") == "run_end" and row.get("class") == "ok":
        tripped = False  # a later clean run resolves the trip
if tripped:
    sys.stderr.write(
        "[swarmlord] circuit breaker: task %s has an unresolved trip in the "
        "ledger. Delegation for this task is paused — read the conflict "
        "report in .git/swarmlord/reports/ and ask the user before retrying.\n" % task)
    sys.exit(2)
sys.exit(0)
PY
