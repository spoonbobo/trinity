# Vault Server Configuration
# For production, replace dev mode with proper unsealing and TLS

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

ui = false

# Lease durations (production: use shorter TTLs with renewal)
default_lease_ttl = "72h"
max_lease_ttl     = "168h"
