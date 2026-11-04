#!/usr/bin/env bash
# adapters/command-code.sh — Command Code (binary: cmd on macOS/Linux, cmdc on Windows, command-code everywhere). Documented exit codes drive a_classify_rc.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="command-code"
a_bin() {
  if command -v cmd >/dev/null 2>&1; then echo cmd;
  elif command -v command-code >/dev/null 2>&1; then echo command-code;
  else echo cmd; fi
}
a_auth_probe() {
  if swarm_guard 15 "$(a_bin)" status >/dev/null 2>&1; then echo ok; else echo bad; fi
}
a_build_cmd() {
  local prompt="$1" full="$2" resume="$3" model="$4"
  CMD=("$(a_bin)" -p)
  # Narrow default: --accept-edits. With NO grant, headless mode blocks all
  # modifying tools. Full trust must be --yolo: the docs warn that
  # --permission-mode yolo does NOT lift the headless block.
  if [ "$full" = "1" ]; then CMD+=(--yolo); else CMD+=(--accept-edits); fi
  CMD+=(--skip-onboarding)
  if [ -n "$resume" ]; then
    if [ "$resume" = "last" ]; then CMD+=(--continue); else CMD+=(--resume "$resume"); fi
  fi
  CMD+=("$prompt")
}
a_classify_rc() {
  case "$1" in
    3) echo auth ;; 4) echo permission ;; 5|10) echo quota ;;
    8) echo failed ;; 9) echo empty ;; *) : ;;
  esac
}
a_resume_supported() { return 0; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
