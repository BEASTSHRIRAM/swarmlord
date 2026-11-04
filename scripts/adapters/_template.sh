#!/usr/bin/env bash
# adapters/_template.sh — copy this to add a new agent.
# 1. Verify the headless command + permission flags against the vendor's
#    official docs or --help. NEVER invent a flag.
# 2. Record what you verified (with source URLs + date) in config/agents.json;
#    mark anything unverified as TODO there.
# 3. Add stub-based tests under tests/ for doctor/run/parse/classify.
AGENT_NAME="template"
a_bin() { echo TODO-binary-name; }
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=("$(a_bin)" TODO-headless-flag "$prompt")
  # [ "$full" = "1" ] && CMD+=(TODO-full-trust-flag)   # opt-in only
  # [ -n "$model" ] && CMD+=(TODO-model-flag "$model")
  # [ -n "$resume" ] && CMD+=(TODO-resume-flag "$resume")
}
# Optional overrides: a_auth_probe (ok|bad|unknown), a_parse, a_classify_rc.
a_resume_supported() { return 1; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
