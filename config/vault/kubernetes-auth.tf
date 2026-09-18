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
# Transit -- NO LONGER USED by the auth service.
#
# It was the signing key: the private key generated inside Vault and never
# readable, with the service sending bytes to be signed. That required a direct
# Vault call on every login. The service now reads its key from a Kubernetes
# Secret that the Vault Secrets Operator syncs, and signs locally, so it makes
# no Vault request at all.
#
# The mount and key are kept rather than deleted because removing them takes
# two applies: deletion_allowed was false, and Vault refuses to delete a key
# while it is. This change flips the flag; a follow-up commit can drop both
# resources once that has been applied.
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

  # Flipped to true so the resource can be removed in a later apply. Vault
  # refuses to delete a key while this is false, and Terraform cannot update
  # and destroy in the same step -- removing the block without this would make
  # the apply fail.
  deletion_allowed = true
}

# ---------------------------------------------------------------------------
# What the auth service may do
# ---------------------------------------------------------------------------

resource "vault_policy" "auth_service" {
  namespace = vault_namespace.backend.path_fq
  name      = "auth-service"

  # Read-only, and only this one path. The Vault Secrets Operator logs in with
  # this policy on the service's behalf and syncs the result into a Kubernetes
  # Secret -- so this is the blast radius of the operator being compromised,
  # not just of the service.
  policy = <<-EOT
    path "${vault_mount.backend_kv.path}/data/auth-service/*" {
      capabilities = ["read"]
    }

    # kv-v2 keeps data and metadata apart; the operator reads metadata to notice
    # a new version and resync.
    path "${vault_mount.backend_kv.path}/metadata/auth-service/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# Binds one ServiceAccount in one Kubernetes namespace to that policy.
#
# The Vault Secrets Operator does not use its own identity here: it requests a
# token for THIS ServiceAccount and logs in as it. So the boundary stays per
# namespace, and a second service gets its own role, policy and path rather
# than sharing one.
#
# Both bounds matter: without bound_service_account_namespaces any namespace
# could create a ServiceAccount called "auth-service" and read these secrets.
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
