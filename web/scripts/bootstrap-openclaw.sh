#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_HOME="/home/node/.openclaw"
SEED_ROOT="/opt/trinity-seed"

seed_dir_if_empty() {
  local src="$1"
  local dst="$2"

  if [ ! -d "$src" ]; then
    return
  fi

  mkdir -p "$dst"
  if [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
    cp -a "$src"/. "$dst"/
    echo "[bootstrap] Seeded $dst from $src"
  else
    echo "[bootstrap] Keeping existing $dst"
  fi
}

seed_dir_if_empty "$SEED_ROOT/skills" "$OPENCLAW_HOME/skills"
seed_dir_if_empty "$SEED_ROOT/cron-templates" "$OPENCLAW_HOME/cron-templates"

exec "$@"
