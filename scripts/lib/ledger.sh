#!/usr/bin/env bash
# ledger.sh — append-only ledger at .git/swarmlord/ledger.jsonl.
# The ledger stores prompt HASHES, never prompt text.
swarm_ledger_file() {  # $1 = repo dir (or any dir inside the repo)
  local gd
  gd="$(git -C "$1" rev-parse --git-dir 2>/dev/null)" || { echo ""; return; }
  case "$gd" in /*) ;; *) gd="$1/$gd" ;; esac
  echo "$gd/swarmlord/ledger.jsonl"
}
swarm_prompt_hash() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
# swarm_ledger_append <ledger> <entry-json>
swarm_ledger_append() {
  [ -n "$1" ] || return 0
  python3 "$SWARM_ROOT/scripts/lib/swarm.py" append --ledger "$1" --entry "$2"
}
# swarm_make_entry: pass swarm.py entry flags through.
swarm_make_entry() { python3 "$SWARM_ROOT/scripts/lib/swarm.py" entry "$@"; }
swarm_error_sig() { python3 "$SWARM_ROOT/scripts/lib/swarm.py" signorm --file "$1"; }
