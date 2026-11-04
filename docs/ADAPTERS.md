# Adapters

One file per agent in `scripts/adapters/`, all implementing the same
interface from `scripts/lib/adapter-base.sh`:

| subcommand | contract |
|---|---|
| `doctor` | exit 0 = installed (auth ok or unknown); 11 = known auth failure; 15 = binary missing. Prints `agent=<id> version=<v> auth=<ok\|unknown>`. |
| `run` | env contract: `SWARM_DIR`, `SWARM_PROMPT`, `SWARM_FULL_TRUST`, `SWARM_RESUME`, `SWARM_MODEL`. Runs headlessly in `SWARM_DIR` with stdin from `/dev/null`; reply on stdout. |
| `parse <file>` | prints the cleaned reply for a raw output file (identity in text mode; JSON extraction when `SWARM_STRUCTURED=1` for agents with a verified JSON mode). |
| `classify <rc> <out> <err>` | echoes one shared class: `ok empty timeout auth quota permission model not_installed failed`. Agent-specific documented exit codes are mapped first (see Command Code, Muse Code), generic text patterns second. |
| `resume-supported` | exit 0/1. |
| `print-cmd` | prints the resolved command line with `<prompt>` as a placeholder. |

## The rules

1. **Never invent a flag.** Every command/flag in an adapter was verified
   against the vendor's official docs or `--help` output, and the sources
   are recorded in `config/agents.json` under `verified_against`.
2. Anything unverified is a `TODO` in `config/agents.json` and the adapter
   header — and the adapter must not use it. Current TODOs: Copilot /
   Gemini / Muse Code auth-status commands, Copilot `--model`, OpenCode
   true full-trust flag, Goose `run` permission-mode flag, Aider headless
   resume, most `min_tested_version` pins.
3. **Narrow grant by default; full trust only when `SWARM_FULL_TRUST=1`.**
4. Add stub tests for every adapter you touch (`tests/run-tests.sh`).

## Per-agent notes

- **codex** — headless defaults to a read-only sandbox; the adapter passes
  `--sandbox workspace-write` as the narrow grant.
- **kiro** — headless requires `KIRO_API_KEY`. Narrow default = no trust
  flags (untrusted calls are denied); `SWARM_TRUST_TOOLS=<ids>` is the
  scoped grant.
- **copilot** — narrow default = `--allow-tool=write --allow-tool=shell`;
  override the list with `SWARM_COPILOT_ALLOW=a,b,c`.
- **gemini** — narrow = `--approval-mode auto_edit`; structured mode
  (`--output-format json`) is parsed for `response` + usage stats.
- **opencode** — permissions are config-driven; `--auto` (full-trust slot)
  still honours explicit deny rules.
- **command-code** — narrow = `--accept-edits` (bare headless mode blocks
  all modifying tools). Full trust must be `--yolo`; per the vendor docs,
  `--permission-mode yolo` does *not* lift the headless block. Documented
  exit codes 0–10 drive its classifier.
- **muse** — narrow unattended posture = `--disable-approval` (sandbox
  stays on). Paid only; no free tier is documented.
- **antigravity** — behaviour carried over from a wrapper verified against
  agy 1.1.8–1.4.4 (`--model` honoured headless only from 1.1.10; JSON from
  1.1.8). Narrow grant = `permissions.allow` rules in agy settings.
- **aider** — git-native: it auto-commits edits, which is safe here because
  its commits land on the run's own branch. No `--yes-always` by default.
- **goose** — **its default permission mode is Autonomous.** The mode is
  config-driven (`goose configure`); the adapter passes no permission flag
  (TODO). Set a narrower mode before delegating write work.
- **local** — HTTP, not a CLI: `POST /v1/chat/completions` against
  `$SWARMLORD_LOCAL_URL` (or the `local_url` plugin option; Ollama default
  `http://localhost:11434`), model from `$SWARMLORD_LOCAL_MODEL`. Reply-only.

## Adding an agent

Copy `scripts/adapters/_template.sh`, verify the CLI's headless surface,
record it in `config/agents.json`, add the binary name to
`tests/stubs/bin/` (copy any existing stub), and extend the adapter loop in
`tests/run-tests.sh` if the generic cases don't cover it.
