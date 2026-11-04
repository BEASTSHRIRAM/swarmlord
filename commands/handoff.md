---
description: Hand a whole test-covered task to one agent; on failure, hand off to a second agent with a full state capsule.
argument-hint: "--dir <repo> --tests <cmd> [--agent <a>] [--handoff-to <b>] <requirement>"
---

Hand off the following task with SwarmLord:

$ARGUMENTS

Rules:
- Only hand off tasks that are **large and test-covered**. Small tasks cost more handed off than done directly — do those yourself.
- Run: `swarmlord-handoff --dir <repo> --tests "<test command>" [--agent <a>] [--handoff-to <b>] "<requirement>"`
- You read nothing while it runs. The first agent's work is gated by the tests; on failure the second agent receives the requirement **plus a capsule** (runs, files changed, test results, errors) generated from the task ledger.
- When it finishes, verify by re-running the tests yourself and reviewing the branch diff. Report the outcome as a first draft for human review, not as finished work.
