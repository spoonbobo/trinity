---
name: dev-sync
description: Sync files between the host machine and the running Trinity Docker containers — config, agent files, skills, and extensions.
license: MIT
metadata:
  audience: developers
  workflow: trinity
---

## What This Skill Covers

Development workflows for syncing files between the host and the `trinity-openclaw` Docker container. During development you frequently need to push local changes into the container or pull live config back to the host.

## Sync Config (Container → Host)

Pull the live OpenClaw config from the Docker volume back to the host:

```bash
docker cp trinity-openclaw:/home/node/.openclaw/openclaw.json src/openclaw.json
git diff src/openclaw.json
```

Review the diff for meaningful config changes before committing.

## Sync Agent Files (Container → Host)

Pull configuration and agent files from the running container:

```bash
# openclaw.json
docker cp trinity-openclaw:/home/node/.openclaw/openclaw.json src/openclaw.json

# Agent models config
docker cp trinity-openclaw:/home/node/.openclaw/agents/main/models.json src/agents/main/models.json

# AGENTS.md from workspace
docker cp trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md src/AGENTS.md

# Check what changed
git diff --stat src/openclaw.json src/agents/main/models.json src/AGENTS.md
```

**Never sync `auth-profiles.json`** — it contains secrets.

## Sync Skills (Host → Container)

Push all skills from the host into the running container:

```bash
docker cp src/skills/. trinity-openclaw:/home/node/.openclaw/skills/
docker exec trinity-openclaw openclaw skills list --json
docker restart trinity-openclaw
```

## Deploy Extensions (Host → Container)

Hot-deploy extensions and AGENTS.md without a full rebuild:

```bash
# Copy canvas-bridge extension
docker cp src/extensions/canvas-bridge/index.ts trinity-openclaw:/home/node/.openclaw/extensions/canvas-bridge/index.ts

# Copy AGENTS.md
docker cp src/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md

# Restart to reload
docker restart trinity-openclaw
```

AGENTS.md changes only take effect on new sessions. Clear the webchat session to force a fresh system prompt.

## Quick Reference

| Direction | What | Command |
|-----------|------|---------|
| Container → Host | openclaw.json | `docker cp trinity-openclaw:/home/node/.openclaw/openclaw.json src/openclaw.json` |
| Container → Host | models.json | `docker cp trinity-openclaw:/home/node/.openclaw/agents/main/models.json src/agents/main/models.json` |
| Container → Host | AGENTS.md | `docker cp trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md src/AGENTS.md` |
| Host → Container | Skills | `docker cp src/skills/. trinity-openclaw:/home/node/.openclaw/skills/` |
| Host → Container | Extensions | `docker cp src/extensions/canvas-bridge/index.ts trinity-openclaw:/home/node/.openclaw/extensions/canvas-bridge/index.ts` |
| Host → Container | AGENTS.md | `docker cp src/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md` |
