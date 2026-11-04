# Security

SwarmLord delegates work to external CLI agents that execute code and edit
files. That is powerful and dangerous in specific, known ways.

## Threat model & mitigations

- **Over-broad agent permissions** → adapters default to the narrowest
  headless grant each CLI offers. Full-trust flags are opt-in per run and
  documented as unsafe outside a disposable container
  ([docs/PERMISSIONS.md](docs/PERMISSIONS.md)).
- **A delegated agent damaging the real tree** → every run works in a
  throwaway git worktree on its own branch; only Claude merges, after
  diffing and running tests.
- **Prompt injection from repository content** → a checked-out repo is
  untrusted input. The `swarmlord-delegate` subagent is fenced by a
  PreToolUse gate (wrapper binaries only, bare names, no pipelines, no
  shell-string options). Narrow grants limit what a hijacked run can do;
  diff review is the last line.
- **Secret leakage through logs** → the ledger stores prompt *hashes*,
  never prompt text, and lives inside `.git/`. Credentials belong to each
  agent CLI's own store or environment — SwarmLord never reads, prints, or
  forwards them, and adapters pass no credential material on command lines
  (Command Code / Muse Code headless auth comes from env vars by design).
- **Runaway or looping agents** → per-task budgets, the circuit breaker,
  per-repo run locks, and wall-clock timeouts bound the blast radius.

## Reporting

Please report vulnerabilities privately via the repository's GitHub
Security Advisories ("Report a vulnerability") rather than a public issue,
and include the adapter, versions, and a minimal reproduction.
