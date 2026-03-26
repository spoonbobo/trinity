# Vault Server Configuration
# TLS: mount cert/key at /vault/tls/ and set tls_disable = "false"
# For dev/minikube, tls_disable = "true" is acceptable behind cluster networking

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = "true"
  tls_cert_file = "/vault/tls/tls.crt"
  tls_key_file  = "/vault/tls/tls.key"
}

ui = false

default_lease_ttl = "1h"
max_lease_ttl     = "24h"
