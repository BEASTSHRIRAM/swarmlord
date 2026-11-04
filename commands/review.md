---
description: Independent cross-agent review of the current diff — a different agent family reads it, Claude reconciles.
argument-hint: "[--agent <name>]"
---

Get an independent review of the current work:

1. Capture the diff scope yourself (files changed, size). If the diff is tiny, review it yourself and skip delegation.
2. Delegate the review: `swarmlord-delegate --task-type review --dir <repo-root> "Review the changes on the current branch. Return findings as a list: severity, file:line, what is wrong, and a suggested fix. Do not edit files."` — add `--agent <name>` from $ARGUMENTS if one was named. Prefer an agent from a **different model family** than the one that wrote the code.
3. Reconcile: check each finding against the code yourself. Report which findings you accept, which you reject (and why), and fix the accepted ones or delegate the fixes explicitly.
