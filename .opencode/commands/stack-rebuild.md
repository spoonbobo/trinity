---
description: Rebuild Flutter frontend and restart the stack
---

Rebuild the Trinity AGI frontend and restart the stack. Run these commands in order:

!`docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder`

Then restart the stack:

!`docker compose -f web/docker-compose.yml up -d`

Report build success/failure and final service status.
