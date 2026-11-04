# Changelog

## [0.1.0] — 2026-11-04

(Working title during development was AgentMux; renamed to SwarmLord before first release.)

Initial release of SwarmLord.

- One entry point (`delegate.sh`) delegating to 11 adapters: Codex, Kiro,
  Copilot, Gemini, OpenCode, Command Code, Muse Code, Antigravity, Aider,
  Goose, and local LLMs (Ollama / LM Studio / OpenAI-compatible), each with
  doctor / run / parse / classify / resume over a shared interface.
- User-editable routing (`config/routing.json`) by task type with
  fallbacks for missing, unauthenticated, and quota-exhausted agents,
  plus quota cooldowns.
- Capability manifest (`config/agents.json`) with every headless command
  and permission flag verified against official vendor docs; unverified
  items marked TODO.
- Per-run git worktree/branch isolation; only Claude merges.
- Ledger-backed circuit breaker (`.git/swarmlord/ledger.jsonl`): state
  recurrence, repeated errors, cross-agent reverts, per-task budget
  overruns → pause, checkpoint commit, conflict report; enforced in the
  wrapper and as a PreToolUse hook.
- Orchestration guards: per-repo run lock, file claims, handoff capsules,
  provenance (agent, version, model, prompt hash — never prompt text).
- Whole-task handoff between agents with test gating; background jobs for
  interactive sessions.
- Stub-based test suite (142 checks) requiring no real agent CLI.
