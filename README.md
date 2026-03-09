# Trinity

## What this repo contains

- Trinity application code
- Docker Compose stack
- Minikube + Helm setup
- Kubernetes chart values and manifests

## Prerequisites

- Docker Desktop with Compose v2
- an LLM provider API key for testing
- for Kubernetes deploy: `minikube`, `kubectl`, and `helm`

## Deploy with Docker Compose

### 1. Configure environment

```bash
cp app/.env.example app/.env
```

Edit `app/.env` and set a gateway token:

```env
OPENCLAW_GATEWAY_TOKEN=<your-token>
```

Generate one if needed:

```bash
openssl rand -hex 32
```

### 2. Build the frontend

```bash
docker compose -f app/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f app/docker-compose.yml --profile build run --rm frontend-builder
```

This compiles the Flutter web app and copies the static files into a shared Docker volume.

### 3. Start the stack

```bash
docker compose -f app/docker-compose.yml up -d
```

### 4. Open the app

- Trinity UI: [http://localhost](http://localhost)
- OpenClaw dashboard: [http://localhost:18789](http://localhost:18789)

Add your LLM provider API keys in the OpenClaw dashboard.

### Rebuild after code changes

```bash
docker compose -f app/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f app/docker-compose.yml --profile build run --rm frontend-builder
docker compose -f app/docker-compose.yml restart nginx
```

## Deploy with Minikube

This Kubernetes path is intended for testing the chart and service wiring on your machine.

### One-command setup

```bash
./k8s/minikube-setup.sh all
```

This script:
- installs required tools if missing
- starts Docker Desktop if needed
- starts Minikube
- builds and loads cluster images
- deploys the Helm chart into `trinity`
- runs bootstrap and migration steps

### Useful commands

```bash
./k8s/minikube-setup.sh start
./k8s/minikube-setup.sh build
./k8s/minikube-setup.sh deploy
./k8s/minikube-setup.sh status
./k8s/minikube-setup.sh teardown
```

### Access the cluster app

Run this in a separate terminal and keep it running:

```bash
minikube tunnel
```

Then open:

- Trinity UI: [http://localhost](http://localhost)
- Keycloak: [http://localhost/keycloak](http://localhost/keycloak)
- Vault UI: [http://vault.localhost/ui/](http://vault.localhost/ui/)
- Grafana: [http://grafana.localhost/login](http://grafana.localhost/login)
- Loki readiness: [http://loki.localhost/ready](http://loki.localhost/ready)

Default bootstrap credentials:
- Trinity admin: `admin@trinity.work` / `admin123`
- Keycloak admin: `admin` / `trinity-kc-admin-123`

## License

See `LICENSE` if present, or contact the maintainers.
