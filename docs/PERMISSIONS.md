# Permissions

Delegated agents execute code and edit files. SwarmLord's posture:
**narrow grants by default, full trust only as an explicit per-run opt-in,
and only inside a disposable container.**

## Default (narrow) grants

| agent | default grant the adapter passes |
|---|---|
| codex | `--sandbox workspace-write` (headless default is a read-only sandbox) |
| kiro | no trust flags — untrusted tool calls are denied; `SWARM_TRUST_TOOLS=<ids>` for a scoped grant |
| copilot | `--allow-tool=write --allow-tool=shell` (override: `SWARM_COPILOT_ALLOW`) |
| gemini | `--approval-mode auto_edit` (`plan` is the read-only mode) |
| opencode | your config's `permission` rules (`allow`/`ask`/`deny`) |
| command-code | `--accept-edits` (bare headless mode blocks all modifying tools) |
| muse | `--disable-approval` — approvals skipped, **OS sandbox stays on** |
| antigravity | `permissions.allow` rules in agy settings (e.g. `write_file(<dir>)`) |
| aider | no `--yes-always` — confirmations decline on a non-TTY |
| goose | ⚠ Goose's own default is **Autonomous** — set a narrower mode via `goose configure` before write tasks |
| local | none possible — the adapter has no file or shell access at all |

## Full trust (opt-in, unsafe)

Passing `--full-trust` to `delegate.sh` (or `swarmlord-handoff`) forwards
the agent's full-trust flag: codex `--dangerously-bypass-approvals-and-sandbox`,
kiro `--trust-all-tools`, copilot `--allow-all`, gemini
`--approval-mode=yolo`, opencode `--auto`, command-code `--yolo`, muse
`--yolo`, antigravity `--dangerously-skip-permissions`, aider
`--yes-always`, goose (already autonomous by default).

**These disable the agent's own safety checks.** Meta's docs say of
`muse --yolo`: use it only on trusted code in a disposable, isolated
container. The same applies to every flag in this list. Never enable full
trust to make a permission denial "go away" — widen the specific grant, or
ask the user.

## Structural protections (always on)

- Runs happen in a **throwaway git worktree**; an agent can only damage
  its own branch, and nothing merges without Claude's verification.
- The `swarmlord-delegate` **subagent** is fenced by
  `hooks/validate-delegate-bash.sh`: it may run only the wrapper binaries
  (bare names, no pipelines/chaining/redirection/substitution), and may
  not pass `--tests` (a shell string) at all.
- The **ledger never stores prompt text** — only its SHA-256 — so audit
  data does not become a secret leak.
- Repository content is **untrusted input**: a checked-out repo can carry
  prompt-injection payloads aimed at a delegated agent. Narrow grants +
  worktree isolation + diff review are the mitigation; treat surprising
  agent behaviour as a security signal, not a curiosity.
