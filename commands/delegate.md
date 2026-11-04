---
description: Delegate a well-scoped task to the best CLI agent (routed by task type), then verify.
argument-hint: "[--agent <name>] [--task-type <type>] <task>"
---

Delegate the following task via SwarmLord, following the `swarmlord` skill's routing and verification rules.

Task: $ARGUMENTS

Do this:
1. Decide the task type (frontend, backend, tests, refactor, docs, research, review) and let routing pick the agent — or pass `--agent <name>` when there is a clear reason. Skip delegation entirely if the task is small or judgement-heavy; do it yourself instead.
2. Run synchronously (you may be headless — do not background-and-wait):
   `swarmlord-delegate [--agent <name>] --task-type <type> --dir <repo-root> "<task>"`
   Add `--tests "<cmd>"` when a test command gates the task, and `--expect-changes` for write tasks so a reply with no file changes counts as a failure.
3. Read the `SWARMLORD_RUN` line on stderr: agent, class, tests, files changed, worktree branch. The run happened in its own worktree on branch `swarmlord/<task>-<agent>` — nothing has been merged.
4. **Verify yourself**: review the worktree diff and run the tests. Never trust the agent's self-reported success. Merge only when your own check passes — only you merge.
5. If the wrapper exits 16, the circuit breaker tripped: read the conflict report it names, summarize what recurred/failed, and ask the user how to proceed. Do not retry the same task blindly.
