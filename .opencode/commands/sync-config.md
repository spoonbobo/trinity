---
description: Sync openclaw.json from container to host
---

Copy the live OpenClaw config from the Docker volume back to the host:

!`docker cp trinity-openclaw:/home/node/.openclaw/openclaw.json app/openclaw.json`

Then show a summary of what changed by running:

!`git diff app/openclaw.json`

Report any meaningful config differences.
