#!/usr/bin/env python3
"""swarm.py — JSON-heavy internals for SwarmLord: routing, ledger, circuit
breaker, file claims, handoff capsules, error signatures.

The ledger is append-only JSONL at .git/swarmlord/ledger.jsonl (path resolved
by the shell side). Privacy rule: the ledger stores prompt HASHES, never
prompt text.
"""
import argparse, hashlib, json, os, re, sys, time

def load_jsonl(path):
    rows = []
    if path and os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except Exception:
                    continue
    return rows

def cmd_route(a):
    with open(a.routing, encoding="utf-8") as f:
        routing = json.load(f)
    if a.agent:
        print(a.agent)
        return 0
    types = routing.get("task_types") or {}
    cands = types.get(a.task_type) or types.get("default") or []
    cooldown = float(routing.get("cooldown_minutes") or 0) * 60
    if cooldown and a.ledger:
        now = time.time()
        benched = set()
        for r in load_jsonl(a.ledger):
            if r.get("class") == "quota" and r.get("agent"):
                ts = float(r.get("ts") or 0)
                if now - ts < cooldown:
                    benched.add(r["agent"])
        kept = [c for c in cands if c not in benched]
        # Never filter the list to empty: if everything is benched, the caller
        # still gets the full list and doctor/fallback logic decides.
        if kept:
            cands = kept
    for c in cands:
        print(c)
    return 0

def cmd_append(a):
    entry = json.loads(a.entry)
    os.makedirs(os.path.dirname(os.path.abspath(a.ledger)), exist_ok=True)
    with open(a.ledger, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, sort_keys=True) + "\n")
    return 0

def cmd_entry(a):
    files = {}
    for spec in (a.files or []):
        parts = spec.split("|")
        if len(parts) == 3:
            files[parts[0]] = {"before": parts[1], "after": parts[2]}
    entry = {
        "ts": time.time(), "task_id": a.task, "agent": a.agent, "event": a.event,
        "class": a.cls, "error_sig": a.error_sig, "tests": a.tests,
        "duration_s": a.duration, "prompt_hash": a.prompt_hash,
        "agent_version": a.version, "model": a.model, "files": files,
        "claims": [c for c in (a.claims or "").split(",") if c],
        "worktree": a.worktree, "branch": a.branch,
    }
    print(json.dumps(entry, sort_keys=True))
    return 0

def cmd_signorm(a):
    try:
        text = open(a.file, encoding="utf-8", errors="replace").read()
    except Exception:
        text = ""
    t = text.lower()
    t = re.sub(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "<uuid>", t)
    t = re.sub(r"0x[0-9a-f]+", "<hex>", t)
    t = re.sub(r"/[^\s:]+", "<path>", t)
    t = re.sub(r"\b\d+\b", "<n>", t)
    t = re.sub(r"\s+", " ", t).strip()[:200]
    if not t:
        print("")
        return 0
    print("sig:%s %s" % (hashlib.sha1(t.encode()).hexdigest()[:12], t[:80]))
    return 0

def cmd_breaker(a):
    rows = [r for r in load_jsonl(a.ledger) if r.get("task_id") == a.task]
    runs = [r for r in rows if r.get("event") == "run_end"]
    handoffs = [r for r in rows if r.get("event") == "handoff"]
    trips = []
    # Budget overruns (per task, cumulative across agents).
    if a.max_runs and len(runs) > a.max_runs:
        trips.append(("budget_runs", "%d runs > budget %d" % (len(runs), a.max_runs)))
    if a.max_handoffs and len(handoffs) > a.max_handoffs:
        trips.append(("budget_handoffs", "%d handoffs > budget %d" % (len(handoffs), a.max_handoffs)))
    total_s = sum(float(r.get("duration_s") or 0) for r in runs)
    if a.max_seconds and total_s > a.max_seconds:
        trips.append(("budget_seconds", "%.0fs total > budget %ds" % (total_s, a.max_seconds)))
    # Repeated error: same signature on the last two consecutive runs.
    if len(runs) >= 2:
        x, y = runs[-2], runs[-1]
        if (x.get("error_sig") and x.get("error_sig") == y.get("error_sig")
                and x.get("class") not in ("ok", "", None)
                and y.get("class") not in ("ok", "", None)):
            trips.append(("repeated_error", "error signature repeated twice in a row: %s" % y["error_sig"]))
    # State recurrence / cross-agent revert, judged on the latest run.
    if runs:
        latest = runs[-1]
        # Build the state sequence per file from all earlier runs.
        seq = {}
        for r in runs[:-1]:
            for path, h in (r.get("files") or {}).items():
                s = seq.setdefault(path, [])
                if not s:
                    s.append(h.get("before"))
                s.append(h.get("after"))
        for path, h in (latest.get("files") or {}).items():
            after = h.get("after")
            if after in (None, "", "ABSENT"):
                continue
            prior = seq.get(path) or []
            if after in prior and prior and prior[-1] != after:
                earlier_agents = {r.get("agent") for r in runs[:-1]
                                  if path in (r.get("files") or {})}
                if latest.get("agent") not in earlier_agents and earlier_agents:
                    trips.append(("cross_agent_revert",
                                  "%s returned to a previous hash (%s) set by another agent" % (path, str(after)[:12])))
                else:
                    trips.append(("state_recurrence",
                                  "%s returned to a previous hash (%s)" % (path, str(after)[:12])))
                break
    if trips:
        kind, detail = trips[0]
        print("TRIP %s %s" % (kind, detail))
        return 16
    print("OK")
    return 0

def cmd_claims(a):
    want = {c for c in (a.files or "").split(",") if c}
    if not want or want == {"*"}:
        # A whole-worktree claim conflicts with any other active claim.
        want = None
    now = time.time()
    stale = a.stale_hours * 3600
    rows = load_jsonl(a.ledger)
    last_claim, last_end = {}, {}
    for r in rows:
        t = r.get("task_id")
        if not t or t == a.task:
            continue
        if r.get("event") == "claim":
            last_claim[t] = r
        if r.get("event") in ("run_end", "trip"):
            last_end[t] = r
    for t, claim in last_claim.items():
        end = last_end.get(t)
        if end and float(end.get("ts") or 0) >= float(claim.get("ts") or 0):
            continue  # that task finished; its claim is released
        if now - float(claim.get("ts") or 0) > stale:
            continue  # stale claim, ignore
        theirs = {c for c in (claim.get("claims") or [])}
        if want is None or not theirs or theirs == {"*"} or (want & theirs):
            print("CONFLICT %s held by task %s" % (",".join(sorted(want & theirs)) if (want and theirs) else "*", t))
            return 17
    print("OK")
    return 0

def cmd_capsule(a):
    rows = [r for r in load_jsonl(a.ledger) if r.get("task_id") == a.task]
    lines = ["# SwarmLord handoff capsule — task %s" % a.task, ""]
    if a.spec_hash:
        lines.append("Task spec (prompt) sha256: `%s` — the receiving agent gets the same spec; this capsule adds state, not a new brief." % a.spec_hash)
        lines.append("")
    agents = []
    for r in rows:
        if r.get("agent") and r["agent"] not in agents:
            agents.append(r["agent"])
    lines.append("Agents so far: %s" % (", ".join(agents) or "none"))
    lines.append("")
    lines.append("## Runs")
    for r in rows:
        if r.get("event") == "run_end":
            lines.append("- %s — class=%s tests=%s duration=%ss version=%s" % (
                r.get("agent"), r.get("class"), r.get("tests") or "-",
                r.get("duration_s"), r.get("agent_version") or "?"))
            if r.get("error_sig"):
                lines.append("  error: %s" % r["error_sig"])
    lines.append("")
    lines.append("## Files changed (latest state)")
    latest = {}
    for r in rows:
        for path, h in (r.get("files") or {}).items():
            latest[path] = h
    for path in sorted(latest):
        h = latest[path]
        lines.append("- `%s`: %s -> %s" % (path, str(h.get("before"))[:12], str(h.get("after"))[:12]))
    if not latest:
        lines.append("- none recorded")
    text = "\n".join(lines) + "\n"
    if len(text) > 6000:
        text = text[:6000] + "\n[truncated — full state is in the ledger]\n"
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text)
    print(text, end="")
    return 0

def cmd_diffsnap(a):
    def load(path):
        d = {}
        if path and os.path.exists(path):
            for line in open(path, encoding="utf-8", errors="replace"):
                line = line.rstrip("\n")
                if "|" in line:
                    k, v = line.rsplit("|", 1)
                    d[k] = v
        return d
    before, after = load(a.before), load(a.after)
    for path in sorted(set(before) | set(after)):
        b, c = before.get(path, "ABSENT"), after.get(path, "ABSENT")
        if b != c:
            print("%s|%s|%s" % (path, b, c))
    return 0

def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    q = sub.add_parser("route"); q.add_argument("--routing", required=True)
    q.add_argument("--task-type", default="default"); q.add_argument("--ledger", default="")
    q.add_argument("--agent", default=""); q.set_defaults(fn=cmd_route)
    q = sub.add_parser("append"); q.add_argument("--ledger", required=True)
    q.add_argument("--entry", required=True); q.set_defaults(fn=cmd_append)
    q = sub.add_parser("entry")
    for k in ("task", "agent", "event", "cls", "error-sig", "tests", "prompt-hash", "version", "model", "worktree", "branch", "claims"):
        q.add_argument("--" + k, default="")
    q.add_argument("--duration", type=float, default=0)
    q.add_argument("--files", action="append", default=[])
    q.set_defaults(fn=cmd_entry)
    q = sub.add_parser("signorm"); q.add_argument("--file", required=True); q.set_defaults(fn=cmd_signorm)
    q = sub.add_parser("breaker"); q.add_argument("--ledger", required=True)
    q.add_argument("--task", required=True); q.add_argument("--max-runs", type=int, default=0)
    q.add_argument("--max-handoffs", type=int, default=0); q.add_argument("--max-seconds", type=float, default=0)
    q.set_defaults(fn=cmd_breaker)
    q = sub.add_parser("claims"); q.add_argument("--ledger", required=True)
    q.add_argument("--task", required=True); q.add_argument("--files", default="*")
    q.add_argument("--stale-hours", type=float, default=6); q.set_defaults(fn=cmd_claims)
    q = sub.add_parser("diffsnap"); q.add_argument("--before", default="")
    q.add_argument("--after", default=""); q.set_defaults(fn=cmd_diffsnap)
    q = sub.add_parser("capsule"); q.add_argument("--ledger", required=True)
    q.add_argument("--task", required=True); q.add_argument("--out", default="")
    q.add_argument("--spec-hash", default=""); q.set_defaults(fn=cmd_capsule)
    a = p.parse_args()
    return a.fn(a)

if __name__ == "__main__":
    sys.exit(main())
