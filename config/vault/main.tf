# Vault configuration: identities, namespaces, PKI and the demo secrets.
#
# Applied against a cluster that already exists; nothing here creates Vault
# itself. The layout follows the namespace model: the root namespace holds the
# certificate authorities and the administrator, and each team namespace owns
# its own auth method, policies and secrets engines, so a tenant can be handed
# over without touching the others.

# ---------------------------------------------------------------------------
# Root namespace: administrator
# ---------------------------------------------------------------------------

resource "vault_auth_backend" "root_userpass" {
  type        = "userpass"
  path        = "userpass"
  description = "Username and password login for the platform administrator."
}

# Equivalent to root, but as a named policy: it can be audited, attached to a
# token with a TTL, and revoked. The initial root token should be revoked once
# this login works (vault token revoke -self).
resource "vault_policy" "admin" {
  name = "admin"

  policy = <<-EOT
    # Every path in this namespace and in every child namespace. From the root
    # namespace a child is addressed by its prefix, for example
    # "hp-dev-backend/secret/data/...", so this glob reaches them too.
    path "*" {
      capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
    }
  EOT
}

resource "vault_generic_endpoint" "admin_user" {
  path                 = "auth/${vault_auth_backend.root_userpass.path}/users/${var.admin_username}"
  ignore_absent_fields = true

  # Reading a userpass user never returns the password, so a read would show a
  # permanent diff.
  disable_read = true

  data_json = jsonencode({
    password       = var.admin_password
    token_policies = [vault_policy.admin.name]
  })
}

# ---------------------------------------------------------------------------
# Root namespace: certificate authorities
# ---------------------------------------------------------------------------

resource "vault_mount" "root_pki" {
  path                      = "root-pki"
  type                      = "pki"
  description               = "Offline-style root certificate authority."
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = tonumber(trimsuffix(var.root_ca_ttl, "h")) * 3600
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.root_pki.path
  type        = "internal"
  common_name = var.pki_common_name
  ttl         = var.root_ca_ttl
  key_type    = "ec"
  key_bits    = 256

  # The private key never leaves Vault with type = "internal", so it is not in
  # Terraform state either.
}

resource "vault_mount" "intermediate_pki" {
  path                      = "intermediate-pki"
  type                      = "pki"
  description               = "Intermediate authority for platform workloads."
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = tonumber(trimsuffix(var.intermediate_ca_ttl, "h")) * 3600
}

resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend     = vault_mount.intermediate_pki.path
  type        = "internal"
  common_name = "${var.pki_common_name} Intermediate"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate" {
  backend     = vault_mount.root_pki.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name = "${var.pki_common_name} Intermediate"
  ttl         = var.intermediate_ca_ttl

  depends_on = [vault_pki_secret_backend_root_cert.root]
}

resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.intermediate_pki.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate.certificate
}

# ---------------------------------------------------------------------------
# Namespaces
# ---------------------------------------------------------------------------

resource "vault_namespace" "backend" {
  path = var.backend_namespace
}

resource "vault_namespace" "frontend" {
  path = var.frontend_namespace
}

# ---------------------------------------------------------------------------
# Backend namespace: eigene Auth, PKI signiert von root-pki, statische Secrets
# ---------------------------------------------------------------------------

resource "vault_auth_backend" "backend_userpass" {
  namespace   = vault_namespace.backend.path_fq
  type        = "userpass"
  path        = "userpass"
  description = "Login for the backend team."
}

resource "vault_mount" "backend_kv" {
  namespace   = vault_namespace.backend.path_fq
  path        = "kv"
  type        = "kv-v2"
  description = "Static secrets owned by the backend team."
}

resource "random_password" "backend_api_key" {
  length           = 40
  special          = true
  override_special = "-_"
}

# Demo payload. The value is generated rather than configured so that nobody is
# tempted to keep a real key in a tfvars file; developers read it from Vault.
resource "vault_kv_secret_v2" "backend_api_key" {
  namespace = vault_namespace.backend.path_fq
  mount     = vault_mount.backend_kv.path
  name      = "api-key"

  data_json = jsonencode({
    api_key = random_password.backend_api_key.result
  })
}

resource "vault_mount" "backend_pki" {
  namespace                 = vault_namespace.backend.path_fq
  path                      = "pki-dev"
  type                      = "pki"
  description               = "Development certificates for the backend team."
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = tonumber(trimsuffix(var.intermediate_ca_ttl, "h")) * 3600
}

# Cross-namespace signing: the request is created inside the tenant namespace,
# signed by the root authority in the root namespace, and the result handed
# back. The tenant never sees the root CA private key.
resource "vault_pki_secret_backend_intermediate_cert_request" "backend_pki" {
  namespace   = vault_namespace.backend.path_fq
  backend     = vault_mount.backend_pki.path
  type        = "internal"
  common_name = "${var.pki_common_name} ${var.backend_namespace}"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_root_sign_intermediate" "backend_pki" {
  backend     = vault_mount.root_pki.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.backend_pki.csr
  common_name = "${var.pki_common_name} ${var.backend_namespace}"
  ttl         = var.intermediate_ca_ttl

  depends_on = [vault_pki_secret_backend_root_cert.root]
}

resource "vault_pki_secret_backend_intermediate_set_signed" "backend_pki" {
  namespace   = vault_namespace.backend.path_fq
  backend     = vault_mount.backend_pki.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.backend_pki.certificate
}

# What developers are actually allowed to issue.
resource "vault_pki_secret_backend_role" "backend_dev" {
  namespace          = vault_namespace.backend.path_fq
  backend            = vault_mount.backend_pki.path
  name               = "dev"
  allowed_domains    = var.pki_allowed_domains
  allow_subdomains   = true
  allow_bare_domains = true
  max_ttl            = var.dev_cert_max_ttl
  key_type           = "ec"
  key_bits           = 256

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.backend_pki]
}

resource "vault_policy" "backend_dev" {
  namespace = vault_namespace.backend.path_fq
  name      = "dev"

  policy = <<-EOT
    # Read and write the team's own static secrets.
    path "${vault_mount.backend_kv.path}/data/*" {
      capabilities = ["create", "read", "update", "patch", "delete", "list"]
    }

    path "${vault_mount.backend_kv.path}/metadata/*" {
      capabilities = ["read", "list", "delete"]
    }

    # Issue development certificates, but only through the role: issuing
    # directly would let a developer choose any common name.
    path "${vault_mount.backend_pki.path}/issue/dev" {
      capabilities = ["create", "update"]
    }

    path "${vault_mount.backend_pki.path}/ca/pem" {
      capabilities = ["read"]
    }

    # Let the UI show what exists without granting access to other mounts.
    path "sys/mounts" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_generic_endpoint" "dev1" {
  namespace            = vault_namespace.backend.path_fq
  path                 = "auth/${vault_auth_backend.backend_userpass.path}/users/dev1"
  ignore_absent_fields = true
  disable_read         = true

  data_json = jsonencode({
    password       = var.dev1_password
    token_policies = [vault_policy.backend_dev.name]
  })
}

# ---------------------------------------------------------------------------
# Frontend namespace: eigene Auth und statische Secrets, keine PKI
# ---------------------------------------------------------------------------

resource "vault_auth_backend" "frontend_userpass" {
  namespace   = vault_namespace.frontend.path_fq
  type        = "userpass"
  path        = "userpass"
  description = "Login for the frontend team."
}

resource "vault_mount" "frontend_kv" {
  namespace   = vault_namespace.frontend.path_fq
  path        = "kv"
  type        = "kv-v2"
  description = "Static secrets owned by the frontend team."
}

resource "random_password" "frontend_api_key" {
  length           = 40
  special          = true
  override_special = "-_"
}

resource "vault_kv_secret_v2" "frontend_api_key" {
  namespace = vault_namespace.frontend.path_fq
  mount     = vault_mount.frontend_kv.path
  name      = "api-key"

  data_json = jsonencode({
    api_key = random_password.frontend_api_key.result
  })
}

resource "vault_policy" "frontend_dev" {
  namespace = vault_namespace.frontend.path_fq
  name      = "dev"

  policy = <<-EOT
    path "${vault_mount.frontend_kv.path}/data/*" {
      capabilities = ["create", "read", "update", "patch", "delete", "list"]
    }

    path "${vault_mount.frontend_kv.path}/metadata/*" {
      capabilities = ["read", "list", "delete"]
    }

    path "sys/mounts" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_generic_endpoint" "dev2" {
  namespace            = vault_namespace.frontend.path_fq
  path                 = "auth/${vault_auth_backend.frontend_userpass.path}/users/dev2"
  ignore_absent_fields = true
  disable_read         = true

  data_json = jsonencode({
    password       = var.dev2_password
    token_policies = [vault_policy.frontend_dev.name]
  })
}

# ---------------------------------------------------------------------------
# Monitoring: read-only access for Checkmk
# ---------------------------------------------------------------------------

# Vault's Prometheus endpoint requires a token. It is deliberately left that
# way: the listener is published through an internet-facing load balancer, and
# unauthenticated_metrics_access would put seal state, token counts and request
# rates on the open internet. Checkmk gets an AppRole with exactly one path
# instead.
resource "vault_policy" "metrics" {
  name = "metrics"

  policy = <<-EOT
    # Prometheus-formatted telemetry, nothing else.
    path "sys/metrics" {
      capabilities = ["read"]
    }

    # Seal and replication state, so a scrape can tell "sealed" from "down".
    path "sys/health" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Machine logins. Currently only the monitoring role."
}

resource "vault_approle_auth_backend_role" "checkmk" {
  backend        = vault_auth_backend.approle.path
  role_name      = "checkmk"
  token_policies = [vault_policy.metrics.name]

  # Short-lived tokens that renew: a leaked scrape token expires on its own.
  token_ttl     = 3600
  token_max_ttl = 14400

  # The scrape comes from the Checkmk host inside the VPC.
  token_bound_cidrs     = var.monitoring_bound_cidrs
  secret_id_bound_cidrs = var.monitoring_bound_cidrs
}

# The role id is not a secret; the secret id is, and is deliberately not created
# here. Generating it in Terraform would put a long-lived credential into state.
# Create it out of band:
#   vault write -f auth/approle/role/checkmk/secret-id
