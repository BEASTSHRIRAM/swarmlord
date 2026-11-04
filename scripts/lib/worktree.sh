#!/usr/bin/env bash
# worktree.sh — one git worktree + branch per delegated run.
# Worktrees live OUTSIDE the repo (a sibling .swarmlord-worktrees dir) so the
# repo itself stays clean. Only Claude merges these branches — the wrapper
# never merges and never pushes.
# swarm_worktree_create <repo> <task-id> <agent> -> prints "<worktree>|<branch>"
swarm_worktree_create() {
  local repo="$1" task="$2" agent="$3"
  local base="$(dirname "$repo")/.swarmlord-worktrees/$(basename "$repo")"
  local wt="$base/$task-$agent" branch="swarmlord/$task-$agent"
  mkdir -p "$base"
  if [ -d "$wt" ]; then printf '%s|%s\n' "$wt" "$branch"; return 0; fi
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo" worktree add "$wt" "$branch" >/dev/null 2>&1 || return 1
  else
    git -C "$repo" worktree add -b "$branch" "$wt" HEAD >/dev/null 2>&1 || return 1
  fi
  printf '%s|%s\n' "$wt" "$branch"
}
# Snapshot "path|hash" lines for every tracked file in $1 (ABSENT is used by
# the caller for files that appear/disappear between snapshots).
swarm_snapshot() {
  local dir="$1" f
  git -C "$dir" ls-files -co --exclude-standard 2>/dev/null | while IFS= read -r f; do
    [ -f "$dir/$f" ] || continue
    printf '%s|%s\n' "$f" "$(git -C "$dir" hash-object -- "$f" 2>/dev/null)"
  done
}
