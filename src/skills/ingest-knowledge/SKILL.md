---
name: ingest-knowledge
description: Ingest, index, and query documents in a claw-scoped knowledge workspace.
homepage: https://github.com/trinityagi/trinity
metadata:
  {
    "openclaw":
      {
        "emoji": "📥",
      },
  }
---

# Ingest Knowledge

Register, extract, chunk, index, and query documents in the retrieval layer for later use by any downstream workflow.

## Purpose

Use this capability when a claw needs knowledge to be available in the retrieval layer but should not own ingestion itself.

Examples:
- pre-index a handbook corpus
- pre-index product docs before an analysis workflow
- load workspace-specific reference materials for another claw

## Responsibilities

- register documents
- extract normalized text
- chunk content with stable identifiers
- index content into the retrieval subsystem
- maintain document metadata, status, and workspace scoping
- run scoped retrieval queries against indexed content

## Workspace Contract

Knowledge must stay in the target claw's derived default workspace, not an arbitrary caller-defined workspace.

Default convention:
- `tenant_<tenantId>__claw_<openclawId>`

Guidelines:
- the ingestion caller should provide claw identity
- Trinity should derive and enforce the workspace before calling the retrieval layer
- downstream claws should consume the same derived workspace

## Query Contract (same workspace only)

After indexing, query through auth-service scoped endpoints for the active OpenClaw:

- `GET /auth/openclaws/:id/lightrag-documents`
- `POST /auth/openclaws/:id/lightrag-documents`
- `POST /auth/openclaws/:id/lightrag-documents/:documentId/ingest`
- `GET /auth/openclaws/:id/lightrag-documents/:documentId/status`
- `GET /auth/openclaws/:id/lightrag-documents/:documentId/chunks`
- `POST /auth/openclaws/:id/lightrag-query` (proxy to `/retrieval/search`)
- `POST /auth/openclaws/:id/lightrag-compare` (proxy to `/retrieval/compare`)

Rules:
- all reads/writes and retrieval queries run in the derived claw workspace
- cross-workspace query/compare is not allowed
- callers must provide OpenClaw identity; workspace is enforced by platform scope
- auth-service scoped routes require a valid user JWT and OpenClaw access
- do not assume unauthenticated callers can discover OpenClaw ids via `/auth/openclaws`
- for service-to-service execution, use a short-lived delegation token minted by `POST /auth/openclaws/:id/delegation-token` and send it via `X-Trinity-Delegation`
- claw-runtime service calls can authenticate with `X-OpenClaw-Gateway-Token` for the same OpenClaw scope, including document delete operations
- for claw-runtime calls, prefer `OPENCLAW_ID` env (UUID) for `:id`; name aliases may resolve but UUID is canonical
- use auth-service base URL for these routes (for example `http://auth-service:18791` via `TRINITY_AUTH_SERVICE_URL`); do not send `/auth/openclaws/*` to the OpenClaw gateway port

## Relationship to OpenClaw Memory

- this skill uses the LightRAG service and its own workspace-scoped index
- LightRAG credentials and runtime config are managed separately (Vault -> `trinity-secrets` -> LightRAG env)
- OpenClaw memory plugin settings do not configure LightRAG retrieval endpoints
- both systems are complementary: memory plugin supports agent memory, LightRAG supports document ingestion and retrieval APIs

## What This Skill Does Not Do

- domain-specific compliance analysis
- requirement classification

Those belong to downstream, domain-specific skills.

## Output

Return:
- document references
- workspace or corpus identifiers
- indexing status
- chunk and citation availability
- retrieval query results when requested
