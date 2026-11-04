#!/usr/bin/env python3
"""local-run.py — the local adapter's runner.

Talks to any OpenAI-compatible chat endpoint (Ollama, LM Studio, ...):
  SWARMLORD_LOCAL_URL    default http://localhost:11434
  SWARMLORD_LOCAL_MODEL  default llama3.1 (TODO: no universal default exists;
                        set this to a model your endpoint actually serves)
  SWARMLORD_LOCAL_API_KEY  optional bearer token
Reply-only by design: a chat endpoint cannot edit files or run tools.
"""
import json, os, sys, urllib.request

def main():
    url = (os.environ.get("SWARMLORD_LOCAL_URL") or os.environ.get("CLAUDE_PLUGIN_OPTION_LOCAL_URL") or "http://localhost:11434").rstrip("/")
    model = os.environ.get("SWARMLORD_LOCAL_MODEL") or os.environ.get("CLAUDE_PLUGIN_OPTION_LOCAL_MODEL") or "llama3.1"
    prompt = os.environ.get("SWARM_PROMPT", "")
    body = json.dumps({"model": model, "stream": False,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request(url + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    key = os.environ.get("SWARMLORD_LOCAL_API_KEY")
    if key:
        req.add_header("Authorization", "Bearer " + key)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            data = json.load(r)
    except Exception as e:
        print("local adapter: endpoint request failed: %s" % e, file=sys.stderr)
        return 2
    try:
        content = data["choices"][0]["message"]["content"]
    except Exception:
        print("local adapter: unexpected response shape: %s" % str(data)[:200], file=sys.stderr)
        return 2
    usage = data.get("usage")
    if usage:
        print("SWARMLORD_USAGE local %s" % json.dumps(usage), file=sys.stderr)
    print(content)
    return 0

if __name__ == "__main__":
    sys.exit(main())
