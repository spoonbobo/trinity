#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_HOME="/home/node/.openclaw"
SEED_ROOT="/opt/trinity-seed"

ensure_config() {
  local key="$1"
  local value="$2"
  if ! openclaw config get "$key" >/dev/null 2>&1; then
    if ! openclaw config set "$key" "$value" >/dev/null 2>&1; then
      echo "[bootstrap] WARN: Failed to set config: $key" >&2
    else
      echo "[bootstrap] Set default config: $key"
    fi
  fi
}

seed_dir_if_empty() {
  local src="$1"
  local dst="$2"

  if [ ! -d "$src" ]; then
    return
  fi

  if ! mkdir -p "$dst"; then
    echo "[bootstrap] ERROR: Failed to create directory: $dst" >&2
    return 1
  fi

  if [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
    cp -a "$src"/. "$dst"/
    echo "[bootstrap] Seeded $dst from $src"
  else
    echo "[bootstrap] Keeping existing $dst"
  fi
}

seed_dir_if_empty "$SEED_ROOT/skills" "$OPENCLAW_HOME/skills"
seed_dir_if_empty "$SEED_ROOT/cron-templates" "$OPENCLAW_HOME/cron-templates"

if ! mkdir -p "$OPENCLAW_HOME/workspace" "$OPENCLAW_HOME/workspace/memory"; then
  echo "[bootstrap] ERROR: Failed to create workspace directories" >&2
  exit 1
fi

if [ ! -f "$OPENCLAW_HOME/workspace/MEMORY.md" ] && [ -f "$SEED_ROOT/workspace/MEMORY.md" ]; then
  cp -a "$SEED_ROOT/workspace/MEMORY.md" "$OPENCLAW_HOME/workspace/MEMORY.md"
  echo "[bootstrap] Seeded $OPENCLAW_HOME/workspace/MEMORY.md"
else
  echo "[bootstrap] Keeping existing $OPENCLAW_HOME/workspace/MEMORY.md"
fi

# ACP defaults (idempotent; only fills missing keys)
ensure_config "plugins.entries.acpx.enabled" "true"
ensure_config "acp.enabled" "true"
ensure_config "acp.dispatch.enabled" "true"
ensure_config "acp.backend" "acpx"
ensure_config "acp.defaultAgent" "opencode"
ensure_config "acp.allowedAgents" '["pi","claude","codex","opencode","gemini"]'
ensure_config "acp.maxConcurrentSessions" "8"
ensure_config "acp.runtime.ttlMinutes" "120"

exec "$@"
