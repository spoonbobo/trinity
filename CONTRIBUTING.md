# Contributing

## Getting started

1. Fork the repo and clone your fork.
2. Follow the [Deployment](#deployment) steps in the README to get the stack running locally.
3. Create a feature branch from `main`.

## Project layout

- `src/frontend/` -- Flutter web shell (Dart)
- `src/nginx/` -- Reverse proxy config
- `src/terminal-proxy/` -- WebSocket terminal proxy (Node.js)
- `src/scripts/` -- Bootstrap and test scripts
- `src/skills/` -- Bundled agent skills
- `src/cron-templates/` -- Bundled cron templates
- `site/` -- Marketing website (Next.js)

## Development workflow

### Frontend (Flutter)

The frontend lives in `src/frontend/`. After making changes:

```bash
# Rebuild the image (no cache to pick up all changes)
docker compose -f src/docker-compose.yml --profile build build --no-cache frontend-builder

# Copy built assets to the shared volume
docker compose -f src/docker-compose.yml --profile build run --rm frontend-builder

# Restart nginx to serve the new build
docker compose -f src/docker-compose.yml restart nginx
```

Hard-refresh your browser (Ctrl+Shift+R) to bypass cache.

### Nginx config

Edit `src/nginx/nginx.conf`, then:

```bash
docker compose -f src/docker-compose.yml restart nginx
```

### Terminal proxy

Edit files in `src/terminal-proxy/`, then:

```bash
docker compose -f src/docker-compose.yml build terminal-proxy
docker compose -f src/docker-compose.yml up -d terminal-proxy
```

### OpenClaw gateway

The gateway image is built from `src/Dockerfile.openclaw`. To rebuild:

```bash
docker compose -f src/docker-compose.yml build openclaw-gateway
docker compose -f src/docker-compose.yml up -d openclaw-gateway
```

## Submitting changes

1. Keep commits focused -- one logical change per commit.
2. Test that the full stack starts cleanly (`docker compose up -d`) and the site loads at http://localhost.
3. Open a pull request against `main` with a clear description of what changed and why.

## Code style

- Dart: follow `flutter_lints` defaults.
- JavaScript/Node: no specific linter enforced yet -- keep it consistent with existing code.
- Nginx: use comments to label each location block.
