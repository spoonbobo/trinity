#!/usr/bin/env bash
# ─── seed-dev-secrets.sh ──────────────────────────────────────────────────
# Seeds development secrets into Vault for local (minikube) usage.
# Run this ONCE after `helm install` to populate Vault with dev secrets.
# After this, vault-sync will propagate them to K8s Secrets automatically.
#
# Usage:
#   ./k8s/seed-dev-secrets.sh [--port-forward]
#
# If --port-forward is passed, the script will set up port-forwarding to Vault.
# Otherwise, it assumes VAULT_ADDR is already reachable (e.g., via minikube tunnel).
set -euo pipefail

NAMESPACE="${NAMESPACE:-trinity}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
export VAULT_ADDR VAULT_TOKEN

# ── Port-forward if requested ──
PF_PID=""
if [ "${1:-}" = "--port-forward" ]; then
  echo "[seed] Starting port-forward to vault..."
  kubectl port-forward svc/vault 8200:8200 -n "$NAMESPACE" &
  PF_PID=$!
  sleep 3
fi

cleanup() {
  if [ -n "$PF_PID" ]; then
    kill "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[seed] Seeding dev secrets into Vault at $VAULT_ADDR..."

# ── supabase ──
vault kv put secret/trinity/supabase \
  jwt_secret="trinity-dev-jwt-secret-at-least-32-chars-long!!" \
  anon_key="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlLWRlbW8iLCJpYXQiOjE3MDk0MDAwMDAsImV4cCI6MTg2NzA4MDAwMH0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE" \
  postgres_password="trinity-pg-password-123"

# ── keycloak ──
vault kv put secret/trinity/keycloak \
  admin="trinity-kc-admin-123" \
  client_secret="trinity-kc-client-secret-123" \
  authentik_client_secret=""

# ── superadmin ──
vault kv put secret/trinity/superadmin \
  allowlist="" \
  enabled="true" \
  email="admin@trinity.work" \
  password="admin123"

# ── orchestrator ──
vault kv put secret/trinity/orchestrator \
  service_token="trinity-orchestrator-token-123"

# ── grafana ──
vault kv put secret/trinity/grafana \
  password="trinity-grafana-123"

# ── lightrag ──
vault kv put secret/trinity/lightrag \
  internal_token="trinity-lightrag-internal-token-123" \
  llm_api_key="" \
  embedding_api_key=""

# ── copilot / zen ──
vault kv put secret/trinity/copilot \
  zen_api_key=""

# ── openclaw (POE key + future skill keys) ──
vault kv put secret/trinity/openclaw \
  poe_api_key="${POE_API_KEY:-}"

echo "[seed] Done. Now run 'helm upgrade' to trigger vault-sync."
echo "[seed] Or manually run the vault-sync job:"
echo "  kubectl create job vault-sync-manual --from=job/vault-sync-<revision> -n $NAMESPACE"
