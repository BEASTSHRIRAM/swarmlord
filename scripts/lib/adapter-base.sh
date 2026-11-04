#!/usr/bin/env bash
# adapter-base.sh — the shared adapter interface. Every adapters/<name>.sh
# defines the a_* functions below and ends with `adapter_dispatch "$@"`.
#
# Interface (subcommands):
#   doctor            exit 0 = installed (auth ok or unknown); 15 = binary
#                     missing; 11 = known auth failure. Prints one line:
#                     agent=<name> version=<v> auth=<ok|unknown>
#   run               env contract: SWARM_DIR SWARM_PROMPT SWARM_FULL_TRUST(0|1)
#                     SWARM_RESUME SWARM_MODEL. Runs the CLI headlessly in
#                     SWARM_DIR, reply on stdout, diagnostics on stderr.
#   parse <file>      print the cleaned reply for a raw run-output file.
#   classify <rc> <out> <err>   echo the shared class for a finished run.
#   resume-supported  exit 0 if resume is supported, 1 otherwise.
#   print-cmd         print the resolved command line (prompt as <prompt>).
#
# An adapter must define: AGENT_NAME, a_bin, a_build_cmd (sets CMD array).
# It may override: a_doctor, a_parse, a_classify_rc, a_version.
set -uo pipefail
SWARM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=common.sh
. "$SWARM_ROOT/scripts/lib/common.sh"

a_version() { swarm_guard 15 "$(a_bin)" --version 2>/dev/null | head -1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Default doctor: binary on PATH + version probe. Adapters with a real
# auth-status command override a_auth_probe to echo ok|bad|unknown.
# Defaults below are only installed when the adapter did not define its own:
# the adapter's functions are defined BEFORE this file is sourced, so an
# unconditional definition here would silently replace them.
if ! declare -F a_auth_probe >/dev/null 2>&1; then a_auth_probe() { echo unknown; }; fi
if ! declare -F a_doctor >/dev/null 2>&1; then a_doctor() {
  local bin; bin="$(a_bin)"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "agent=$AGENT_NAME version= auth=missing" ; return 15
  fi
  local ver auth
  ver="$(a_version)"
  auth="$(a_auth_probe)"
  if [ "$auth" = "bad" ]; then
    echo "agent=$AGENT_NAME version=$ver auth=bad"; return 11
  fi
  echo "agent=$AGENT_NAME version=$ver auth=$auth"
  return 0
}
fi

if ! declare -F a_parse >/dev/null 2>&1; then a_parse() { cat "$1"; }; fi  # text-mode default

# Agent-specific exit-code mapping hook: echo a class or nothing.
if ! declare -F a_classify_rc >/dev/null 2>&1; then a_classify_rc() { :; }; fi

a_classify() {
  local rc="$1" out="$2" err="$3" mapped
  mapped="$(a_classify_rc "$rc" "$out" "$err")"
  if [ -n "$mapped" ]; then echo "$mapped"; return; fi
  if ! command -v "$(a_bin)" >/dev/null 2>&1; then echo not_installed; return; fi
  swarm_classify_generic "$rc" "$out" "$err"
}

if ! declare -F a_resume_supported >/dev/null 2>&1; then a_resume_supported() { return 1; }; fi

a_run() {
  local -a CMD
  a_build_cmd "${SWARM_PROMPT:-}" "${SWARM_FULL_TRUST:-0}" "${SWARM_RESUME:-}" "${SWARM_MODEL:-}"
  cd "${SWARM_DIR:-.}" || return 2
  "${CMD[@]}" < /dev/null
}

a_print_cmd() {
  local -a CMD
  a_build_cmd "<prompt>" "${SWARM_FULL_TRUST:-0}" "${SWARM_RESUME:-}" "${SWARM_MODEL:-}"
  printf '%s ' "${CMD[@]}"; echo
}

adapter_dispatch() {
  local sub="${1:-}"
  case "$sub" in
    doctor) a_doctor ;;
    run) a_run ;;
    parse) a_parse "${2:?parse needs a file}" ;;
    classify) a_classify "${2:-0}" "${3:-/dev/null}" "${4:-/dev/null}" ;;
    resume-supported) a_resume_supported ;;
    print-cmd) a_print_cmd ;;
    *) echo "adapter $AGENT_NAME: unknown subcommand '${sub}'" >&2; return 1 ;;
  esac
}
