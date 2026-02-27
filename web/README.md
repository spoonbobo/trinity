# Trinity AGI - Universal Command Center

A "featureless" agentic shell powered by [OpenClaw](https://docs.openclaw.ai).
The UI is a blank canvas; the agent and user build functionality together.

## Architecture

- **OpenClaw Gateway** (Docker) -- agent engine, multi-provider LLM, tools, governance, sessions, multi-channel
- **Flutter Web Shell** -- blank canvas host, A2UI renderer, voice input, governance panel
- **nginx** -- serves Flutter build, proxies WebSocket + API to OpenClaw

## Quick Start

### Prerequisites

- Docker Desktop (with Docker Compose v2)
- An LLM provider API key (Anthropic, OpenAI, or local via Ollama)

### 1. Configure

```bash
cd web
cp .env.example .env
# Edit .env: set OPENCLAW_GATEWAY_TOKEN and at least one provider API key
```

### 2. Build & Run

```bash
# Build the Flutter frontend
docker compose --profile build run --rm frontend-builder

# Start the stack
docker compose up -d
```

### 3. Open

- **Trinity Shell**: http://localhost (Flutter UI)
- **OpenClaw Control UI**: http://localhost:18789 (built-in dashboard)

## Configuration

- `web/openclaw.json` -- OpenClaw gateway configuration (tools, providers, sandbox, auth)
- `web/.env` -- API keys and gateway token
- `web/nginx/nginx.conf` -- reverse proxy settings

## Project Structure

```
web/
  docker-compose.yml          # OpenClaw gateway + Flutter builder + nginx
  openclaw.json               # Gateway config
  .env                        # Secrets
  nginx/nginx.conf            # Reverse proxy
  frontend/
    lib/
      main.dart               # App entry point
      core/
        gateway_client.dart   # OpenClaw WebSocket client
        protocol.dart         # Protocol constants
        auth.dart             # Gateway auth
      features/
        shell/                # Blank canvas host
        prompt_bar/           # Text + voice input
        chat/                 # Streaming chat view
        canvas/               # A2UI renderer + WebView
        governance/           # Exec + workflow approval panel
      models/
        ws_frame.dart         # WebSocket frame types
        a2ui_models.dart      # A2UI v0.8 models
```

## How It Works

1. The Flutter shell connects to OpenClaw Gateway via WebSocket
2. User types or speaks a request in the prompt bar
3. OpenClaw runs the agent (LLM + tools), streams responses back
4. Agent can push A2UI surfaces to the Canvas panel
5. High-risk actions trigger approval gates in the Governance panel
6. Users can also interact via WhatsApp, Telegram, Discord (multi-channel)
