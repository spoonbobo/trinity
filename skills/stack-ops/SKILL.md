---
name: stack-ops
description: Manage the Trinity AGI Docker Compose stack — start, stop, logs, rebuild frontend, and full deploy.
license: MIT
metadata:
  audience: developers
  workflow: trinity
---

## What This Skill Covers

Docker Compose lifecycle operations for the Trinity AGI stack running from `src/docker-compose.yml`.

## Start Stack

```bash
docker compose -f src/docker-compose.yml up -d
```

Check service status after starting.

## Stop Stack

```bash
docker compose -f src/docker-compose.yml down
```

## View Logs

All services:

```bash
docker compose -f src/docker-compose.yml logs --tail 50
```

Single service (e.g. OpenClaw gateway):

```bash
docker compose -f src/docker-compose.yml logs openclaw-gateway --tail 100
```

Summarize errors, warnings, or notable events. If there are connection issues or crash loops, suggest fixes.

## Rebuild Frontend Only

When Flutter/Dart source changes need to be deployed without touching backend services.

**CRITICAL:** `run --rm frontend-builder` alone does NOT rebuild the image — it reuses the cached one. You MUST `build --no-cache` first.

```bash
# 1. Rebuild Docker image (busts layer cache — REQUIRED for source changes)
docker compose -f src/docker-compose.yml --profile build build --no-cache frontend-builder

# 2. Run builder to copy build output to the volume
docker compose -f src/docker-compose.yml --profile build run --rm frontend-builder

# 3. Restart nginx to serve the new build
docker restart trinity-nginx
```

Remind the user to hard-refresh the browser (Ctrl+Shift+R).

## Full Deploy

Complete rebuild of frontend + backend after source changes across multiple services.

```bash
# 1. Rebuild frontend image (--no-cache)
docker compose -f src/docker-compose.yml --profile build build --no-cache frontend-builder

# 2. Copy frontend build to volume
docker compose -f src/docker-compose.yml --profile build run --rm frontend-builder

# 3. Rebuild backend services (--no-cache)
docker compose -f src/docker-compose.yml build --no-cache terminal-proxy auth-service

# 4. Restart backend services
docker compose -f src/docker-compose.yml up -d terminal-proxy auth-service

# 5. Restart nginx
docker restart trinity-nginx

# 6. Update AGENTS.md in gateway container
docker cp src/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md

# 7. Check service health
docker compose -f src/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}"
```

Remind user to Ctrl+Shift+R in the browser.

## Service Health Check

```bash
docker compose -f src/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}"
```

## Quick Reference

| Action | Command |
|--------|---------|
| Start | `docker compose -f src/docker-compose.yml up -d` |
| Stop | `docker compose -f src/docker-compose.yml down` |
| Logs (all) | `docker compose -f src/docker-compose.yml logs --tail 50` |
| Logs (one) | `docker compose -f src/docker-compose.yml logs <service> --tail 100` |
| Status | `docker compose -f src/docker-compose.yml ps` |
| Rebuild frontend | Build `--no-cache` → run builder → restart nginx |
| Full deploy | Build frontend + backend → restart all → sync AGENTS.md |
