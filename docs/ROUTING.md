# Routing

`config/routing.json` is the user's file. The shipped values are defaults
with fallbacks, not claims about which agent is "best".

## Resolution

For a run, the wrapper resolves the routing file in this order:

1. `$SWARMLORD_ROUTING` (explicit path),
2. `<repo>/.swarmlord/routing.json` (per-project override),
3. `<plugin>/config/routing.json` (shipped defaults).

For the candidate list: `--agent <name>` beats routing entirely. Otherwise
the list is `task_types[<type>]` (or `task_types.default`), filtered by
**cooldowns**: an agent whose latest quota-classified run is younger than
`cooldown_minutes` is skipped (unless that would empty the list). Doctor
then gates each candidate at run time — missing or unauthenticated agents
are skipped with the failure ledgered.

## Shipped defaults

| task type | order |
|---|---|
| frontend | gemini, codex, copilot, opencode |
| backend | codex, copilot, opencode, muse |
| tests | copilot, codex, aider, gemini |
| refactor | codex, aider, opencode, antigravity |
| docs | gemini, local, aider, copilot |
| research | gemini, antigravity, goose, local |
| review | copilot, codex, muse, gemini |
| default | codex, gemini, copilot |

Rationale, briefly: frontend goes to Gemini first for its large context;
review prefers an agent from a different family than typical authors;
docs/research can fall back to `local` because they are reply-only tasks.
Disagree? Edit the file — that is what it is for.

## Budgets

```json
"budgets": {
  "per_task": {"max_runs": 8, "max_handoffs": 3, "max_seconds": 3600, "max_cost_usd": null},
  "per_run_timeout": "10m"
}
```

Budgets are **per task, cumulative across agents and handoffs** — that is
the point: ten individually-cheap runs are one expensive task. Exceeding
one trips the circuit breaker. `max_cost_usd` is recorded for future
accounting; token/cost metering depends on what each CLI reports and is
not enforced yet (see the TODO in `config/agents.json` entries).

## Inspecting a decision

`swarmlord-route --task-type frontend` prints the ordered candidates with
live doctor status, so you can see who would run and who is skipped before
spending anything.
