#!/usr/bin/env bash
# common.sh — shared constants and helpers for SwarmLord.
#
# Shared exit codes (every adapter's classify maps onto these):
#   0 ok | 1 usage | 2 agent failed | 3 empty output | 10 timeout | 11 auth
#   12 quota | 13 permission denied | 14 model unavailable | 15 not installed
#   16 circuit-breaker trip | 17 file-claim conflict
EX_OK=0; EX_USAGE=1; EX_FAILED=2; EX_EMPTY=3; EX_TIMEOUT=10; EX_AUTH=11
EX_QUOTA=12; EX_PERMISSION=13; EX_MODEL=14; EX_NOT_INSTALLED=15
EX_BREAKER=16; EX_CONFLICT=17

# Windows (Git Bash / MSYS / Cygwin): native Python writes CRLF to stdout, and
# bash keeps the '\r', so `mapfile`/`$(...)` yield values like "codex\r" that
# never match a file or a string. Wrap python3 to strip CR, preserving its exit
# status, and export the wrapper so child scripts (adapters, libs) inherit it.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    python3() { command python3 "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; }
    export -f python3
    ;;
esac

swarm_timeout_cmd() {  # echoes a usable timeout command name, or nothing
  if command -v timeout >/dev/null 2>&1; then echo timeout;
  elif command -v gtimeout >/dev/null 2>&1; then echo gtimeout; fi
}

# Run "$@" bounded by $1 seconds when a timeout command exists; returns the
# command's exit code, or 124/137 when the guard had to kill it.
swarm_guard() {
  local secs="$1"; shift
  local to; to="$(swarm_timeout_cmd)"
  if [ -n "$to" ]; then "$to" --kill-after=5 "$secs" "$@"; else "$@"; fi
}

# Parse a duration like 300, 300s, 5m, 1h into seconds. Echoes the number.
swarm_duration_secs() {
  local d="$1"
  case "$d" in
    *h) echo $(( ${d%h} * 3600 )) ;;
    *m) echo $(( ${d%m} * 60 )) ;;
    *s) echo "${d%s}" ;;
    *)  echo "$d" ;;
  esac
}

# Classify a finished run. $1 = exit code, $2 = stdout file, $3 = stderr file.
# Echoes one class: ok empty timeout auth quota permission model not_installed failed
# Pattern order matters: timeout (by exit code) first, then quota before auth
# (a 429 body often also says "unauthorized" in prose), then auth, permission, model.
swarm_classify_generic() {
  local rc="$1" out="$2" err="$3" blob=""
  [ -f "$out" ] && blob="$(cat "$out" 2>/dev/null)"
  [ -f "$err" ] && blob="$blob
$(cat "$err" 2>/dev/null)"
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then echo timeout; return; fi
  local lc; lc="$(printf '%s' "$blob" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in
    *quota*|*"rate limit"*|*rate_limit*|*"too many requests"*|*resource_exhausted*|*"insufficient credits"*|*"usage limit"*|*"429"*) echo quota; return ;;
  esac
  case "$lc" in
    *"not authenticated"*|*unauthenticated*|*"authentication failed"*|*"login required"*|*"invalid api key"*|*unauthorized*|*"401"*) echo auth; return ;;
  esac
  case "$lc" in
    *"permission denied"*|*"denied permission"*|*"not permitted"*|*auto-denied*|*"permission approval is not supported"*) echo permission; return ;;
  esac
  case "$lc" in
    *"unknown model"*|*"invalid --model"*|*"not a known model"*|*"model not found"*) echo model; return ;;
  esac
  if [ "$rc" -eq 0 ]; then
    if [ -s "$out" ]; then echo ok; else echo empty; fi
  else
    echo failed
  fi
}

swarm_exit_for_class() {
  case "$1" in
    ok) echo 0 ;; empty) echo 3 ;; timeout) echo 10 ;; auth) echo 11 ;;
    quota) echo 12 ;; permission) echo 13 ;; model) echo 14 ;;
    not_installed) echo 15 ;; *) echo 2 ;;
  esac
}
