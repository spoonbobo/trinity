---
name: flutter-shell
description: Develop the Trinity AGI Flutter Web Shell — understand the architecture, A2UI renderer, WebSocket models, dual-client pattern, design tokens, and build workflow.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: trinity-agi
---

## What This Skill Covers

The Flutter Web Shell is the frontend for Trinity AGI. It is an intentionally "empty" command center — no static features, no predefined dashboards. The agent and user build functionality together at runtime via A2UI surfaces and chat.

Source: `web/frontend/`

## Architecture

The shell opens **two** concurrent WebSocket connections to the OpenClaw Gateway:

1. **`GatewayClient`** (`lib/core/gateway_client.dart`) — connects as `operator` role. Handles chat I/O (`chat.send`, `chat.history`, `chat.abort`), exec approvals (`exec.approval.resolve`), and receives streaming `chat` + `agent` events.

2. **`NodeClient`** (`lib/core/node_client.dart`) — connects as `node` role with `canvas` capability. The gateway routes `canvas.a2ui`, `canvas.present`, `canvas.hide`, `canvas.navigate`, `canvas.eval`, `canvas.snapshot` commands here. It parses A2UI JSONL payloads and emits them on a `canvasEvents` stream.

Both clients share the same `GatewayAuth` (token + device identity) from `lib/core/auth.dart`.

State management: **Riverpod**. Providers live in `shell_page.dart`:
- `gatewayClientProvider` — the operator connection
- `nodeClientProvider` — the canvas node connection

## Shell Layout (`lib/features/shell/shell_page.dart`)

```
┌──────────────────────────────────────────┐
│ Status Bar (connection dot + label)      │
├──────────────────────┬───────────────────┤
│                      │  Canvas Panel     │
│   ChatStreamView     │  (A2UIRenderer)   │
│                      │       OR          │
│                      │  Governance Panel │
│                      │  (ApprovalPanel)  │
├──────────────────────┴───────────────────┤
│ PromptBar (text input + toggle buttons)  │
└──────────────────────────────────────────┘
```

- Canvas and Governance panels slide in from the right (flex 4 of 10).
- Only one side panel at a time.
- When neither is open, ChatStreamView takes full width.

## WebSocket Frame Models (`lib/models/ws_frame.dart`)

Three frame types matching the OpenClaw protocol:

- `WsRequest` — `{type:"req", id, method, params}`, serialized via `encode()`
- `WsResponse` — `{type:"res", id, ok, payload|error}`, deserialized via `fromJson()`
- `WsEvent` — `{type:"event", event, payload, seq?, stateVersion?}`, deserialized via `fromJson()`
- `WsFrame.parse(raw)` — factory that dispatches to the correct type

## A2UI Model (`lib/models/a2ui_models.dart`)

A2UI v0.8 component protocol. Key classes:

- `A2UISurface` — identified by `surfaceId`, holds a list of `A2UIComponent` and optional `rootId`
- `A2UIComponent` — `{id, type, props}`, parsed from `{id, component: {TypeName: {props...}}}`
- `SurfaceUpdate` — batch of components for a surface
- `BeginRendering` — marks which component is the root
- `DataModelUpdate` — live data binding updates
- `DeleteSurface` — removes a surface

## A2UI Renderer (`lib/features/canvas/a2ui_renderer.dart`)

Listens on both operator events (event names `canvas`, `a2ui`, `canvas.*`) and node `canvasEvents`. Handles four payload keys:

| Payload key | Action |
|---|---|
| `surfaceUpdate` | Replace component list for a surface |
| `beginRendering` | Set the root component ID |
| `dataModelUpdate` | Refresh bound data |
| `deleteSurface` | Remove a surface |

Supported A2UI component types for rendering:
`Text`, `Column`, `Row`, `Button`, `Card`, `Image`, `TextField`, `Slider`, `Toggle`, `Progress`, `Divider`, `Spacer`

Text props can be a plain string, or `{literalString: "..."}` / `{value: "..."}`.
Children props can be a `List<String>` of IDs or `{explicitList: [...]}`.
Button `action` props send `/action <action>` as a chat message.

## Chat Stream (`lib/features/chat/chat_stream.dart`)

Displays four entry types: `user`, `assistant`, `tool`, `system`.

Event handling:
- `chat` events with `state: "delta"` → streaming assistant bubble with blinking cursor
- `chat` events with `state: "final"` → finalized assistant bubble
- `agent` events with `stream: "lifecycle"` → thinking indicator (phase start/end)
- `agent` events with `stream: "tool_call"` → tool card (pending)
- `agent` events with `stream: "tool_result"` → tool card (completed)

On reconnect, loads history via `chat.history`.

## Governance (`lib/features/governance/approval_panel.dart`)

Two approval types:
- **Exec approvals** — from `exec.approval.requested` events. Resolved via `exec.approval.resolve`.
- **Lobster workflow approvals** — from agent `tool_result` with `status: "needs_approval"`. Resolved by sending `/lobster resume <token> --approve|--reject` as chat.

## Design Tokens

| Token | Value |
|---|---|
| Background | `#0A0A0A` |
| Surface / card | `#141414` |
| Border | `#2A2A2A` |
| Status bar bg | `#0F0F0F` |
| Primary (green) | `#6EE7B7` |
| Secondary (blue) | `#3B82F6` |
| Error (red) | `#EF4444` |
| Warning (amber) | `#FBBF24` |
| Text primary | `#E5E5E5` |
| Text secondary | `#B0B0B0` |
| Text muted | `#6B6B6B` |
| Text ghost | `#3A3A3A` |
| Font family | `monofur` (custom, loaded from `fonts/`) |
| User bubble bg | `#1A2A1A`, border `#2A4A2A` |
| Tool card bg | `#0F1520`, border `#1E3A5F` |
| Exec approval bg | `#1A1500`, border `#4A3A00` |
| Workflow approval bg | `#0F1520`, border `#1E3A5F` |

## Dependencies (`pubspec.yaml`)

- `web_socket_channel` — WebSocket connection
- `speech_to_text` — on-device voice transcription
- `flutter_riverpod` — state management
- `uuid` — idempotency keys and device IDs
- `json_annotation` / `json_serializable` — model serialization (build_runner)

## Build & Deploy

The Flutter app is built inside Docker via the `frontend-builder` profile. The Dockerfile COPYs source from `web/frontend/` into the image and runs `flutter build web`.

### CRITICAL: Docker build cache

**`docker compose run --rm frontend-builder` does NOT rebuild the image** — it only runs the existing image's CMD (copies build output to the volume). If you changed any Dart source files, you MUST rebuild the image first:

```bash
# Step 1: Rebuild the image (REQUIRED after any source change)
docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder

# Step 2: Run the builder to copy output to the volume
docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder

# Step 3: Restart nginx to serve the new build
docker restart trinity-nginx
```

Without `--no-cache` (or at minimum `build` before `run`), Docker reuses the cached image layer and your source changes are silently ignored. This is the #1 cause of "my changes aren't working" issues.

### Deploying canvas-bridge extension changes

The canvas-bridge extension (`web/extensions/canvas-bridge/index.ts`) lives in the `openclaw-data` Docker volume. To update it without nuking the volume (which would lose WhatsApp auth, sessions, credentials):

```bash
# Copy updated file directly into the running container
docker cp web/extensions/canvas-bridge/index.ts trinity-openclaw:/home/node/.openclaw/extensions/canvas-bridge/index.ts

# Restart gateway to reload the extension
docker restart trinity-openclaw
```

### Deploying AGENTS.md changes

The agent bootstrap files live in the workspace inside the `openclaw-data` volume:

```bash
docker cp web/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md
docker restart trinity-openclaw
```

**Note:** Existing sessions cache the system prompt from when they were created. Changes to AGENTS.md only take effect on NEW sessions. To force a fresh session, delete the session file and entry from `sessions.json` inside the container.

### Full deploy checklist (after frontend + extension + AGENTS.md changes)

```bash
# 1. Rebuild frontend image (--no-cache to bust Docker cache)
docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder

# 2. Copy build output to volume
docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder

# 3. Copy extension + AGENTS.md into container
docker cp web/extensions/canvas-bridge/index.ts trinity-openclaw:/home/node/.openclaw/extensions/canvas-bridge/index.ts
docker cp web/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md

# 4. Restart services
docker restart trinity-nginx
docker restart trinity-openclaw

# 5. Wait for healthy
timeout 30 bash -c 'while ! docker inspect --format={{.State.Health.Status}} trinity-openclaw | grep -q healthy; do sleep 3; done'

# 6. Tell user to hard-refresh browser (Ctrl+Shift+R)
```

### Verifying the build includes your changes

Search for known strings in the built JS (Dart tree-shakes identifiers, so search for string literals from your code like debugPrint messages):

```bash
docker run --rm -v web_flutter-build:/build alpine grep -c 'YOUR_UNIQUE_STRING' /build/main.dart.js
```

### Gateway token

The gateway token must be passed at build time:
```
--dart-define=GATEWAY_TOKEN=...
```
This is handled automatically via `OPENCLAW_GATEWAY_TOKEN` in `web/.env` → docker-compose build arg → Dockerfile `--dart-define`.

## Do Not

- Do not add static features, navigation bars, sidebars, or menus
- Do not import heavy UI frameworks — the shell stays minimal
- Do not hardcode the gateway URL — use `String.fromEnvironment('GATEWAY_WS_URL')`
- Do not bypass governance — all exec approvals require explicit user consent
