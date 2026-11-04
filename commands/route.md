---
description: Show which agent routing would pick for a task type, and why (doctor status, cooldowns).
argument-hint: "[--task-type <type>]"
---

Run `swarmlord-route --task-type <type from $ARGUMENTS, default: default>` in the current repo and show the ordered candidate list with each agent's live status. Explain in one line why the first ready agent wins and which agents are skipped (missing, auth, or in quota cooldown). If the user wants a different order, point them at `config/routing.json` (or a per-project `.swarmlord/routing.json`) — routing is theirs to edit.
