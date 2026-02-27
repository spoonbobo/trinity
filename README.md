# Trinity AGI — Universal Command Center

A "featureless" agentic shell powered by [OpenClaw](https://docs.openclaw.ai).
The UI is a blank canvas; the agent and user build functionality together at runtime.

## Architecture

- **OpenClaw Gateway** (Docker) — agent engine, multi-provider LLM, tools, governance, sessions, multi-channel messaging.
- **Flutter Web Shell** — blank canvas host, A2UI renderer, voice input, governance panel.
- **nginx** — serves Flutter build, proxies WebSocket + API to the Gateway.

## Quick Start

1. Install Docker Desktop (with Compose v2) and have an LLM provider API key ready.
2. `cp web/.env.example web/.env` and fill in your keys.
3. Build the frontend: `docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder`
4. Start the stack: `docker compose -f web/docker-compose.yml up -d`
5. Open http://localhost for the Trinity Shell, or http://localhost:18789 for the OpenClaw dashboard.

## Repository Structure

- **`web/`** — The command center application (Flutter frontend + OpenClaw Gateway, orchestrated with Docker Compose).
- **`site/`** — The public marketing website (Next.js, Tailwind CSS, dark theme).

## How It Works

1. The Flutter shell connects to OpenClaw Gateway via WebSocket.
2. User types or speaks a request in the prompt bar.
3. OpenClaw runs the agent (LLM + tools) and streams responses back.
4. The agent can push interactive A2UI surfaces to the Canvas.
5. High-risk actions trigger approval gates in the Governance panel.
6. Users can also interact via WhatsApp, Telegram, Discord, and other channels.
