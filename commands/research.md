---
description: Delegate research legwork to a research-routed agent; Claude verifies the sources before using any of it.
argument-hint: "<topic>"
---

Research: $ARGUMENTS

1. Delegate the legwork: `swarmlord-delegate --task-type research --dir <repo-root> "<topic — return claims with a source URL for each>"`.
2. Treat the reply as unverified leads. Open the key sources yourself and cross-check every load-bearing claim against at least two sources before presenting it.
3. Present only what you verified, with the source links. Say plainly which claims you could not verify.
