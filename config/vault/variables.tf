variable "vault_address" {
  description = "Address of the Vault cluster, for example https://<nlb-hostname>:8200."
  type        = string

  validation {
    condition     = can(regex("^https://", var.vault_address))
    error_message = "vault_address must be an https URL; Vault is configured with TLS enabled."
  }
}

variable "vault_token" {
  description = "Token used to apply this configuration. Supply it as a sensitive variable in HCP Terraform. The initial root token works for the first apply; afterwards use a token from the admin userpass login created here, and revoke the root token."
  type        = string
  sensitive   = true
}

variable "vault_ca_cert_file" {
  description = "CA certificate that signed Vault's server certificate. Defaults to the copy committed next to this configuration: cert-manager's CA is private, so no public trust store knows it, and the runner has no other way to obtain it. The file holds a certificate and no key, which is why it can live in a public repository. Rebuilding the environment regenerates the CA — refresh the file then, see the README."
  type        = string
  default     = "vault-ca.pem"
}

variable "vault_tls_server_name" {
  description = "Name the server certificate is verified against, when it differs from the host in vault_address. Defaults to the in-cluster service name, which is what cert-manager issued the certificate for; the load balancer's generated hostname is not in it. Set this to null only when vault_address itself is covered by the certificate."
  type        = string
  default     = "vault.vault.svc.cluster.local"
}

variable "vault_skip_tls_verify" {
  description = "Skip verification of Vault's TLS certificate. Acceptable only for a throwaway environment: it disables the check that would catch a man-in-the-middle."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Identities
# ---------------------------------------------------------------------------

variable "admin_username" {
  description = "Username of the administrator created in the root namespace."
  type        = string
  default     = "timkrebs"

  validation {
    condition     = can(regex("^[a-z0-9_-]{2,32}$", var.admin_username))
    error_message = "admin_username must be 2 to 32 lowercase letters, digits, hyphens or underscores."
  }
}

variable "admin_password" {
  description = "Password for the administrator. Set it as a sensitive variable in HCP Terraform; it is never generated here."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters."
  }
}

variable "dev1_password" {
  description = "Password for dev1, the developer scoped to the backend namespace."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.dev1_password) >= 12
    error_message = "dev1_password must be at least 12 characters."
  }
}

variable "dev2_password" {
  description = "Password for dev2, the developer scoped to the frontend namespace."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.dev2_password) >= 12
    error_message = "dev2_password must be at least 12 characters."
  }
}

# ---------------------------------------------------------------------------
# Namespaces and PKI
# ---------------------------------------------------------------------------

variable "backend_namespace" {
  description = "Namespace for the backend team."
  type        = string
  default     = "hp-dev-backend"
}

variable "frontend_namespace" {
  description = "Namespace for the frontend team."
  type        = string
  default     = "hp-dev-frontend"
}

variable "pki_common_name" {
  description = "Common name of the root certificate authority."
  type        = string
  default     = "hashi-platform Root CA"
}

variable "pki_allowed_domains" {
  description = "Domains the development role may issue certificates for. Subdomains are allowed."
  type        = list(string)
  default     = ["dev.hashi-platform.internal"]

  validation {
    condition     = length(var.pki_allowed_domains) > 0
    error_message = "pki_allowed_domains must list at least one domain, otherwise the role can issue nothing."
  }
}

variable "root_ca_ttl" {
  description = "Lifetime of the root CA certificate in hours. The default is ten years."
  type        = string
  default     = "87600h"
}

variable "intermediate_ca_ttl" {
  description = "Lifetime of the intermediate CA certificates in hours. The default is five years."
  type        = string
  default     = "43800h"
}

variable "dev_cert_max_ttl" {
  description = "Longest certificate lifetime developers may request, in hours."
  type        = string
  default     = "720h"
}

variable "kubernetes_host" {
  description = "API server address Vault uses for TokenReview. From inside the cluster this is the in-cluster service, not the EKS endpoint."
  type        = string
  default     = "https://kubernetes.default.svc:443"

  validation {
    condition     = can(regex("^https://", var.kubernetes_host))
    error_message = "kubernetes_host must be an https URL."
  }
}
