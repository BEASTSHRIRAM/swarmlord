---
name: swarmlord
description: Delegate coding work from Claude Code to many CLI coding agents — Codex, Kiro, Copilot, Gemini, OpenCode, Command Code, Muse Code, Antigravity, Aider, Goose, or a local LLM — through one entry point, with user-configurable routing by task type, per-run git worktree isolation, filesystem + test verification, cross-agent handoff, and a ledger-backed deadlock circuit breaker. Use when the user wants to delegate, hand off, or route work to another coding agent/CLI, run a second-model review, or spread a large build across several agents. Claude stays the orchestrator: it specs, routes, verifies, and is the only one that merges.
version: 0.1.0
---

# SwarmLord — Claude orchestrates, CLI agents execute

One entry point:

```bash
swarmlord-delegate [--agent <name>] --task-type <type> --dir <repo-root> [--tests "<cmd>"] [--expect-changes] "<task>"
```

Claude keeps requirements, architecture, judgement calls, verification, and
merging. Delegated agents do well-scoped, high-volume execution. The value is
the structure around the agents — routing, isolation, verification, and the
circuit breaker — not raw generation.

## 1. When delegation is worth it

**Delegate** when a unit of work is:

- large and well-scoped (scaffolding, exhaustive test generation, migrations,
  mechanical refactors, bulk edits across many files),
- test-covered, so success is checkable without trusting the agent,
- independent enough to run in its own worktree without your minute-by-minute
  judgement,
- a second opinion (review/research) where a *different model family* is the
  point.

**Skip delegation** (do it yourself) when the task is:

- small or one-off — the spec + round-trip + verification costs more than
  doing it,
- judgement-heavy, ambiguous, or still being designed,
- a tiny fix in code you already have in context.

This break-even judgment is yours on every task. The routing defaults never
make it for you.

## 2. Choosing an agent

Routing lives in `config/routing.json` and is **the user's to edit** — treat
the shipped order as defaults, not as facts about which agent is best:

| task type | default order (first healthy wins) |
|---|---|
| frontend | gemini, codex, copilot, opencode |
| backend | codex, copilot, opencode, muse |
| tests | copilot, codex, aider, gemini |
| refactor | codex, aider, opencode, antigravity |
| docs | gemini, local, aider, copilot |
| research | gemini, antigravity, goose, local |
| review | copilot, codex, muse, gemini |

- Per-project override: `<repo>/.swarmlord/routing.json`. Per run: `--agent`.
- `swarmlord-route --task-type <type>` shows the live decision with doctor
  status (missing / auth / quota cooldown) before you commit to it.
- The wrapper walks the list automatically when an agent is **missing,
  unauthenticated, or out of quota** (a quota failure benches that agent for
  `cooldown_minutes`). Timeout / permission / hard failures do **not** fall
  through — a second agent would double the spend or repeat the denial.
- Capability facts (headless command, permission flags, JSON output, resume,
  cost tier, minimum tested version) live in `config/agents.json`. If a field
  there says TODO, it is unverified — do not rely on it.
- The `local` adapter is reply-only (a chat endpoint cannot edit files).
  Use it for docs/research/review drafts, never for write tasks. For a local
  model that *can* edit files, route to goose/opencode pointed at the local
  endpoint instead.
- Goose's default permission mode is Autonomous — check its configured mode
  before delegating write tasks to it.

## 3. Running a delegation

```bash
swarmlord-delegate --task-type backend --dir ~/repo \
  --tests "npm test" --expect-changes \
  "Implement the /invoices endpoint per SPEC.md. End your reply with a short digest: files changed, decisions, anything unfinished."
```

- Always pass `--dir <repo-root>` so the agent reads the real files; do not
  paste code into the prompt.
- Pass `--task-id <stable id>` when several runs belong to one task — the
  ledger, budgets, claims, and the circuit breaker are all keyed by it.
- Ask for a **digest**, not a dump: files changed, key decisions, what's left.
  Bulky detail belongs in files, not in your context.
- Long task in an **interactive** session: `swarmlord-job start ...`, then
  `/swarmlord:status` and `/swarmlord:result <id>`. In headless `claude -p`,
  always delegate synchronously — there is no later turn to collect a job.
- Permissions: adapters run with **narrow grants by default** (see
  `docs/PERMISSIONS.md`). `--full-trust` is per-run, opt-in, and only for a
  disposable container. Never pass it to make a denial go away quietly —
  surface the denial instead.

## 4. Verifying the result

The wrapper prints one machine line on stderr:

```
SWARMLORD_RUN {"task_id": "...", "agent": "codex", "class": "ok", "tests": "pass", "files_changed": 3, "branch": "swarmlord/<task>-codex", ...}
```

1. `class` must be `ok` (anything else is a classified failure: timeout,
   auth, quota, permission, empty, failed — see the exit codes in
   `scripts/lib/common.sh`).
2. Review the diff **in the run's worktree/branch** — the agent worked in
   isolation; nothing is merged yet.
3. Run the tests **yourself**, in a clean state. An agent's self-reported
   "tests pass" is a claim, not evidence.
4. `files_changed: 0` on a write task means the work did not happen, however
   good the reply sounds. (With `--expect-changes` the wrapper already
   classifies that as `empty`.)
5. Only you merge, and only after your own check passes. The wrapper never
   merges and never pushes.

## 5. Handing off between agents

```bash
swarmlord-handoff --dir ~/repo --agent codex --handoff-to gemini \
  --tests "pytest -q" "Implement the export feature per SPEC.md"
```

- The first agent's work is gated by the tests. On failure, the second agent
  receives the **original requirement plus a capsule** — every run, file
  change (with hashes), test result, and error recorded for the task — so it
  continues from real state instead of starting over or guessing.
- Handoffs count against the per-task budget (`max_handoffs`). One handoff is
  the normal shape; a task that keeps failing across agents is a spec problem
  or a circuit-breaker case, not a reason to try a third agent.
- The same flow works mid-task via `--task-id`: run agent A with
  `swarmlord-delegate --task-id T`, then agent B with the same `--task-id T`
  and the capsule from `.git/swarmlord/handoffs/T.md` appended to the prompt.

## 6. The circuit breaker

Every run appends to `.git/swarmlord/ledger.jsonl`: agent, task id, touched
files' before/after blob hashes, normalized error signature, test result,
duration, agent version, and the prompt's **hash** (never its text).

The breaker trips — pausing the task — on:

- **state recurrence**: a file returns to a hash it had earlier in the task,
- **repeated errors**: the same error signature on two consecutive runs,
- **cross-agent reverts**: one agent restores a state another agent moved
  away from,
- **budget overruns**: per-task runs / handoffs / total seconds exceed
  `config/routing.json` budgets.

On a trip the wrapper checkpoint-commits the worktree, writes a conflict
report to `.git/swarmlord/reports/`, exits **16**, and a PreToolUse hook
blocks further delegation for that task until a clean run resolves it.
**When it trips: stop, read the report, summarize it for the user, and ask.**
Never retry a tripped task unchanged, never delete ledger entries, and never
raise the budget just to make the trip go away without telling the user.

Other orchestration guards you get for free: a per-repo run lock (runs on
one repo serialize), file claims (a second task claiming files an active
task holds is refused with exit 17), and agent cooldowns after quota trips.

## 7. Failures worth knowing

| exit | class | what to do |
|---|---|---|
| 3 | empty | agent replied but produced nothing usable (or changed no files with `--expect-changes`) — sharpen the spec or change agent |
| 10 | timeout | narrow the task or raise `--timeout` deliberately |
| 11 | auth | the agent needs its own login step (see `config/agents.json`) — tell the user, never fake it |
| 12 | quota | the wrapper already fell through to the next candidate; if all are benched, report and wait out the cooldown |
| 13 | permission | the narrow grant refused a tool — widen the *specific* grant in that agent's config, or ask the user before considering `--full-trust` |
| 16 | breaker | see section 6 |
| 17 | claim conflict | another task holds those files — serialize, or re-scope this task's `--files` |

## 8. Commands

`/swarmlord:setup` (doctor for all agents) · `/swarmlord:delegate` ·
`/swarmlord:handoff` · `/swarmlord:review` · `/swarmlord:research` ·
`/swarmlord:agents` · `/swarmlord:route` · `/swarmlord:status` ·
`/swarmlord:result` · `/swarmlord:cancel`. Full detail: README.md and docs/.
