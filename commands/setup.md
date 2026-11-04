---
description: Health-check every SwarmLord adapter (installed + authenticated + version) and the plugin wiring.
---

Run the SwarmLord doctor and report status.

Run: `swarmlord-doctor`

Then summarize for the user:
- Which agents are ready, which are not installed, and which have an auth problem.
- Whether `config/agents.json`, `config/routing.json`, and the plugin manifest parse.
- For anything failing, the exact fix (install command or auth step) from that agent's entry in `config/agents.json`.

Keep it short and actionable. Do not delegate anything as part of setup.
