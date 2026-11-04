# Contributing to SwarmLord

SwarmLord is open source (MIT). Contributions are welcome — especially new
adapters and verification fixes.

## Ground rules

1. **Never invent a CLI flag.** An adapter may only use commands/flags
   verified against the vendor's official docs or the installed CLI's
   `--help`. Record the source URL and date in `config/agents.json`
   (`verified_against`); mark anything else `TODO` and don't use it.
2. **Narrow permissions by default.** Full-trust flags are opt-in
   (`SWARM_FULL_TRUST=1`) and must be documented as unsafe outside a
   container in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).
3. **Every behaviour change needs a stub test.** The suite
   (`bash tests/run-tests.sh`) fakes every agent binary — no real CLI, no
   network, no tokens. If a change can't be tested with stubs, say why in
   the PR.
4. Keep the shared exit codes and the adapter interface stable; agents are
   interchangeable *because* the interface is boring.

## Development

```bash
bash tests/run-tests.sh        # full suite
bash scripts/doctor.sh         # wiring + live agent status
```

Layout: `scripts/` (entry points + `adapters/` + `lib/`), `config/`
(agents + routing), `commands/`, `hooks/`, `skills/`, `agents/`, `tests/`,
`docs/`. See [docs/ADAPTERS.md](docs/ADAPTERS.md) for the adapter contract
and how to add an agent.

## Pull requests

- One topic per PR; describe the user-visible change and how you tested it.
- Update `config/agents.json`, docs, and CHANGELOG in the same PR when
  behaviour or capability claims change.
