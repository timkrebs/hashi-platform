# ---------------------------------------------------------------------------
# Kubernetes auth and JWT signing for in-cluster services
#
# Everything above authenticates humans with userpass. This file authenticates
# workloads: a pod presents its ServiceAccount token, Vault verifies it with the
# cluster's TokenReview API and hands back a Vault token carrying a policy.
#
# This works only because the Vault server's own ServiceAccount is bound to
# system:auth-delegator (the chart's server.authDelegator, already in place) --
# that is what lets Vault call TokenReview at all. Without it every login fails
# with "permission denied" and the cause is not visible from the client side.
# ---------------------------------------------------------------------------

resource "vault_auth_backend" "backend_kubernetes" {
  namespace   = vault_namespace.backend.path_fq
  type        = "kubernetes"
  path        = "kubernetes"
  description = "Workload identity for services running in the dev cluster."
}

resource "vault_kubernetes_auth_backend_config" "backend" {
  namespace       = vault_namespace.backend.path_fq
  backend         = vault_auth_backend.backend_kubernetes.path
  kubernetes_host = var.kubernetes_host

  # Deliberately no token_reviewer_jwt and no kubernetes_ca_cert. Vault runs
  # inside the cluster, so it uses its own pod's ServiceAccount token and CA
  # bundle for the TokenReview call. Pinning a reviewer JWT here would embed a
  # credential in Terraform state and break the moment it is rotated.
  disable_local_ca_jwt = false
}

# ---------------------------------------------------------------------------
# JWT signing key
#
# Transit, not KV: the private key is generated inside Vault and can never be
# read out (exportable = false). The auth service sends the bytes it wants
# signed and gets a signature back -- it never holds the key, so a compromised
# pod cannot mint tokens after it is stopped.
#
# The cost is honest and worth stating: Vault becomes a hard runtime dependency
# for issuing tokens. Verification stays independent, because verifiers use the
# public key from JWKS.
# ---------------------------------------------------------------------------

resource "vault_mount" "backend_transit" {
  namespace   = vault_namespace.backend.path_fq
  path        = "transit"
  type        = "transit"
  description = "Signing and encryption keys that never leave Vault."
}

resource "vault_transit_secret_backend_key" "auth_service_jwt" {
  namespace = vault_namespace.backend.path_fq
  backend   = vault_mount.backend_transit.path
  name      = "auth-service-jwt"

  # rsa-2048 because the tokens are RS256. Transit also offers ecdsa-p256 for
  # ES256, which produces shorter tokens; RSA is the wider-compatible default
  # for anything that consumes JWKS.
  type       = "rsa-2048"
  exportable = false

  # Rotation is a Vault operation, not a Terraform one. Old versions stay
  # available for verification, so tokens signed before a rotation keep working
  # until they expire:
  #   vault write -f -namespace=hp-dev-backend transit/keys/auth-service-jwt/rotate
  deletion_allowed = false
}

# ---------------------------------------------------------------------------
# What the auth service may do
# ---------------------------------------------------------------------------

resource "vault_policy" "auth_service" {
  namespace = vault_namespace.backend.path_fq
  name      = "auth-service"

  policy = <<-EOT
    # Sign JWTs. "update" is the capability Transit's sign endpoint requires --
    # there is no separate "sign" capability.
    path "${vault_mount.backend_transit.path}/sign/${vault_transit_secret_backend_key.auth_service_jwt.name}" {
      capabilities = ["update"]
    }

    # Read the public key to serve JWKS. This returns only public material.
    path "${vault_mount.backend_transit.path}/keys/${vault_transit_secret_backend_key.auth_service_jwt.name}" {
      capabilities = ["read"]
    }
  EOT
}

# Binds one ServiceAccount in one Kubernetes namespace to that policy. Both
# bounds matter: without bound_service_account_namespaces any namespace could
# create a ServiceAccount called "auth-service" and sign tokens.
resource "vault_kubernetes_auth_backend_role" "auth_service" {
  namespace = vault_namespace.backend.path_fq
  backend   = vault_auth_backend.backend_kubernetes.path
  role_name = "auth-service"

  bound_service_account_names      = ["auth-service"]
  bound_service_account_namespaces = ["auth-service"]
  token_policies                   = [vault_policy.auth_service.name]

  # Short TTL, renewed by the Vault Agent sidecar. The pod never holds a
  # long-lived credential.
  token_ttl     = 3600
  token_max_ttl = 14400
}
