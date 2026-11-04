# Troubleshooting

**Start with `/swarmlord:setup`** (or `swarmlord-doctor`). It reports every
agent's status and the exact fix for most problems.

## By exit code

| code | meaning | fix |
|---|---|---|
| 3 | empty output / no file changes on a write task | sharpen the task spec; check the agent actually has a write grant; try another agent |
| 10 | timeout | narrow the task, or raise `--timeout` (default 10m) deliberately |
| 11 | auth | run the agent's own login once (`codex login`, `kiro-cli login`, `cmd login`, sign in via `agy`/`muse`, …); headless Kiro needs `KIRO_API_KEY`, headless Muse Code in CI needs `META_API_KEY` |
| 12 | quota | the wrapper falls through automatically; if every candidate is benched, wait out `cooldown_minutes` or check the plan |
| 13 | permission | the narrow grant refused a tool — widen the *specific* grant (see [PERMISSIONS.md](PERMISSIONS.md)); do not reach for `--full-trust` outside a container |
| 14 | model | the `--model` name is not available on that agent's plan — check the agent's own model list |
| 15 | not installed | install the CLI, or remove it from your routing |
| 16 | circuit breaker | read `.git/swarmlord/reports/<task>-*.md`, decide with the user, and only then rerun — a clean run resolves the trip |
| 17 | claim conflict | another task holds those files; wait for it, or re-scope with `--files` |

## Common situations

- **"Agent said done but nothing changed."** Working as designed if you
  passed `--expect-changes` (exit 3). Without it, check `files_changed` in
  the `SWARMLORD_RUN` line and the worktree diff — the usual cause is a
  missing write grant on that agent.
- **A run hangs.** The wrapper's wall-clock guard kills it at the timeout
  and classifies it `timeout`. Some CLIs hang headless without a TTY on
  native Windows — use WSL/macOS/Linux.
- **Stale repo lock.** If a run died hard, `.git/swarmlord/lock` may remain.
  Confirm no delegation is running, then delete that directory.
- **Local adapter "not installed".** No endpoint answered at
  `$SWARMLORD_LOCAL_URL` (default `http://localhost:11434`). Start Ollama /
  LM Studio, or set the URL/model plugin options, then re-run doctor.
- **Routing picks an agent you don't want.** Edit `config/routing.json`
  or drop a `.swarmlord/routing.json` into the project. `swarmlord-route`
  shows the effective decision.
- **Where is the state?** Everything lives under `.git/swarmlord/`:
  `ledger.jsonl`, `reports/`, `handoffs/`, `jobs/`. Worktrees live in the
  sibling `.swarmlord-worktrees/` directory.
