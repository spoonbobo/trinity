#!/bin/sh
# Vault initialization and secrets configuration script

VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN must be set}"

export VAULT_ADDR
export VAULT_TOKEN

echo "[vault-init] Waiting for Vault to be ready..."
count=0
while [ $count -lt 30 ]; do
  if vault status > /dev/null 2>&1; then
    echo "[vault-init] Vault is ready"
    break
  fi
  sleep 2
  count=$((count + 1))
done

if [ $count -ge 30 ]; then
  echo "[vault-init] Timeout waiting for Vault"
  exit 1
fi

# Log partial token only (never log full token)
echo "[vault-init] Using token: $(echo "$VAULT_TOKEN" | cut -c1-4)..."

# Enable KV secrets engine v2 (ignore error if already enabled)
echo "[vault-init] Enabling KV secrets engine..."
vault secrets enable -version=2 kv 2>/dev/null \
  || vault secrets enable -path=secret -version=2 kv 2>/dev/null \
  || echo "[vault-init] KV engine already enabled (ok)"

sleep 1

# Validate required env vars -- fail if critical secrets are missing or set to test values
validate_secret() {
  local name="$1" value="$2"
  if [ -z "$value" ] || [ "$value" = "test" ] || [ "$value" = "test-jwt" ] || [ "$value" = "test-anon" ] || [ "$value" = "test-pg" ]; then
    echo "[vault-init] ERROR: $name is unset or uses a test default. Set it in .env"
    return 1
  fi
  return 0
}

echo "[vault-init] Writing secrets..."

# Supabase secrets
if validate_secret "SUPABASE_JWT_SECRET" "$SUPABASE_JWT_SECRET" && \
   validate_secret "SUPABASE_ANON_KEY" "$SUPABASE_ANON_KEY" && \
   validate_secret "SUPABASE_POSTGRES_PASSWORD" "$SUPABASE_POSTGRES_PASSWORD"; then
  vault kv put secret/trinity/supabase \
    jwt_secret="$SUPABASE_JWT_SECRET" \
    anon_key="$SUPABASE_ANON_KEY" \
    postgres_password="$SUPABASE_POSTGRES_PASSWORD" \
    2>&1 || echo "[vault-init] WARN: failed to write supabase secrets"
else
  echo "[vault-init] WARN: Skipping supabase secrets (invalid values)"
fi

# Keycloak secrets
if validate_secret "KEYCLOAK_ADMIN_PASSWORD" "$KEYCLOAK_ADMIN_PASSWORD"; then
  vault kv put secret/trinity/keycloak \
    admin="$KEYCLOAK_ADMIN_PASSWORD" \
    client_secret="${KEYCLOAK_CLIENT_SECRET:-}" \
    2>&1 || echo "[vault-init] WARN: failed to write keycloak secrets"
else
  echo "[vault-init] WARN: Skipping keycloak secrets (invalid values)"
fi

# Auth service secrets
if validate_secret "OPENCLAW_GATEWAY_TOKEN" "$OPENCLAW_GATEWAY_TOKEN"; then
  vault kv put secret/trinity/auth-service \
    token="$OPENCLAW_GATEWAY_TOKEN" \
    2>&1 || echo "[vault-init] WARN: failed to write auth-service secrets"
else
  echo "[vault-init] WARN: Skipping auth-service secrets (invalid values)"
fi

# Superadmin configuration
vault kv put secret/trinity/superadmin \
  allowlist="${SUPERADMIN_ALLOWLIST:-}" \
  enabled="${ENABLE_DEFAULT_SUPERADMIN:-true}" \
  2>&1 || echo "[vault-init] WARN: failed to write superadmin config"

echo "[vault-init] Secrets configured"
echo "[vault-init] Vault ready at $VAULT_ADDR"
