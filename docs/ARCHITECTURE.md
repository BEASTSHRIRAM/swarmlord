# Architecture

## Components

```
Claude Code ── swarmlord-delegate (bin shim) ── scripts/delegate.sh
                                                  │
        ┌──────────────────┬──────────────────────┼─────────────────────┐
     router             adapters               worktree              ledger
  routing.json      adapters/<name>.sh    git worktree per run   .git/swarmlord/
  + doctor gate     doctor|run|parse|     branch swarmlord/       ledger.jsonl
  + cooldowns       classify|resume       <task>-<agent>         + breaker
                                                  │
                              handoff.sh ── capsule (ledger → markdown)
                              job.sh     ── background runs (interactive)
```

- **`scripts/delegate.sh`** — the only entry point. Parses flags, resolves
  routing, takes the per-repo run lock, registers file claims, then for each
  candidate: doctor → worktree → snapshot → run (wall-clock guarded) →
  classify → snapshot/diff → optional tests → ledger → circuit breaker.
- **`scripts/adapters/<name>.sh`** — one file per agent over
  `scripts/lib/adapter-base.sh`. See [ADAPTERS.md](ADAPTERS.md).
- **`scripts/lib/swarm.py`** — the JSON internals: routing, ledger append,
  error-signature normalization, breaker checks, claims, capsules, snapshot
  diffs. Bash stays the glue; Python owns the JSON.
- **`scripts/handoff.sh`** — whole-task protocol: agent A gated by tests;
  on failure, a handoff event + capsule, then agent B.
- **`scripts/job.sh`** — background jobs for interactive sessions
  (start/status/result/cancel), stored under `.git/swarmlord/jobs/`.
- **Hooks** — SessionStart policy injection + agent presence check,
  UserPromptSubmit delegation nudge, and a **PreToolUse circuit-breaker
  gate** that blocks further delegation for a task with an unresolved trip.
  The `swarmlord-delegate` subagent additionally sits behind
  `hooks/validate-delegate-bash.sh`, which allows it to run *only* the
  wrapper binaries, as bare names, with no pipelines and no `--tests`
  (a test command is a shell string and belongs to the main session).

## Run lifecycle and fallback

1. Candidates come from `routing.json` (task type → ordered list), or from
   `--agent`. Quota-cooldowned agents are filtered by the router.
2. An agent whose doctor fails (missing → 15, auth → 11) is ledgered and
   skipped. A run classified `quota`, `auth`, or `not_installed` also falls
   through to the next candidate.
3. `timeout`, `permission`, `model`, `empty`, and `failed` do **not** fall
   through: a second agent would double the spend, repeat the denial, or
   mask the real problem. The classified exit code is returned instead.
4. Success returns the agent's reply on stdout and one `SWARMLORD_RUN` JSON
   line on stderr (agent, class, tests, files changed, duration, worktree,
   branch) for the orchestrator to act on.

Shared exit codes: `0` ok · `1` usage · `2` failed · `3` empty · `10`
timeout · `11` auth · `12` quota · `13` permission · `14` model · `15`
not installed · `16` circuit-breaker trip · `17` file-claim conflict.

## The ledger

Append-only JSONL at `.git/swarmlord/ledger.jsonl` (inside `.git`, so it
never pollutes the working tree or a diff). One entry per event
(`claim`, `run_end`, `handoff`, `trip`) with: timestamp, task id, agent,
agent version, model, class, normalized error signature, test result,
duration, files touched with **before/after blob hashes**, claims, worktree
and branch, and the prompt's SHA-256. **Prompt text is never stored.**

## Circuit breaker

Checked after every run (and enforced pre-run by the hook). Trips on:

- **state recurrence** — a file's new hash equals an earlier state in the
  same task (and is not the immediately previous state),
- **cross-agent revert** — the recurrence was produced by a *different*
  agent than the one that set the earlier state,
- **repeated error** — identical normalized error signature on two
  consecutive runs of the task,
- **budget overrun** — per-task runs, handoffs, or cumulative seconds over
  the `routing.json` budgets.

On a trip the wrapper checkpoint-commits the worktree branch, writes
`.git/swarmlord/reports/<task>-<time>.md` (trip detail + capsule), ledgers a
`trip` event, prints the run's reply, and exits 16. A later clean (`ok`)
run for the same task resolves the trip for the PreToolUse hook.

## Orchestration guards

- **Worktree isolation** — runs never share a working tree; worktrees live
  in a sibling `.swarmlord-worktrees/` directory.
- **Run lock** — one active delegation per repo (`.git/swarmlord/lock`),
  because ledger/breaker accounting assumes serialized runs.
- **File claims** — a run claims files (`--files`, default `*` = whole
  worktree). A second task claiming overlapping files while the first is
  active is refused (exit 17). Claims release on the task's next
  `run_end`/`trip`, or go stale after 6 hours.
- **Cooldowns** — a quota-classified run benches that agent for
  `cooldown_minutes` (router-side, from ledger timestamps).
- **Handoff capsules** — `.git/swarmlord/handoffs/<task>.md`, generated
  purely from ledger state, capped at 6000 chars so a capsule cannot blow
  the receiving agent's context.
- **Provenance** — agent + version + model + prompt hash per run makes any
  delegation reproducible and auditable after the fact.
