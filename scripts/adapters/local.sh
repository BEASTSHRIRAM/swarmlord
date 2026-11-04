#!/usr/bin/env bash
# adapters/local.sh — Local LLM adapter (Ollama / LM Studio / any OpenAI-compatible endpoint). Reply-only: it cannot edit files, so it fits docs/research/review task types. For a local model that CAN edit files, point goose or opencode at the local endpoint and use those adapters.
# Verified against official docs on 2026-11-04 — see config/agents.json for
# the source URLs and the full capability record. Anything not verified there
# is marked TODO and is not used.

AGENT_NAME="local"
a_bin() { echo curl; }
a_doctor() {
  local url="${SWARMLORD_LOCAL_URL:-${CLAUDE_PLUGIN_OPTION_LOCAL_URL:-http://localhost:11434}}"
  if python3 -c '
import json, sys, urllib.request
url = sys.argv[1].rstrip("/") + "/v1/models"
try:
    with urllib.request.urlopen(url, timeout=5) as r:
        data = json.load(r)
    ids = [m.get("id", "?") for m in (data.get("data") or [])]
    print(ids[0] if ids else "unknown")
except Exception:
    sys.exit(1)
' "$url" > /tmp/swarmlord-local-model.$$ 2>/dev/null; then
    echo "agent=local version=$(cat /tmp/swarmlord-local-model.$$) auth=ok"
    rm -f /tmp/swarmlord-local-model.$$
    return 0
  fi
  rm -f /tmp/swarmlord-local-model.$$
  echo "agent=local version= auth=missing"
  echo "local adapter: no OpenAI-compatible endpoint answering at $url (set SWARMLORD_LOCAL_URL)" >&2
  return 15
}
a_build_cmd() {
  CMD=(python3 "$SWARM_ADAPTER_DIR/local-run.py")
}
a_resume_supported() { return 1; }
SWARM_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SWARM_ADAPTER_DIR/../lib/adapter-base.sh"
adapter_dispatch "$@"
