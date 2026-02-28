---
description: Check OpenClaw Gateway health and status
---

Check the Trinity OpenClaw Gateway status. Run:

!`docker exec trinity-openclaw openclaw status`

And the health check:

!`docker exec trinity-openclaw openclaw health --token $OPENCLAW_GATEWAY_TOKEN`

Summarize the gateway state, uptime, and any issues.
