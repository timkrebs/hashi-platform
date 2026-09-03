variable "region" {
  description = "AWS region the environment is deployed to."
  type        = string
  default     = "us-east-1"
}

variable "vault_allowed_cidrs" {
  description = "Source ranges allowed to reach the Vault API through its public load balancer."
  type        = list(string)

  validation {
    condition     = length(var.vault_allowed_cidrs) > 0 && alltrue([for cidr in var.vault_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "vault_allowed_cidrs must contain at least one valid IPv4 CIDR; an empty list would expose Vault to the internet."
  }
}

variable "enable_cert_manager" {
  description = "Install cert-manager. Vault's self-signed CA and server certificate are issued through it."
  type        = bool
  default     = true
}

variable "vault_kms_key_deletion_window_in_days" {
  description = "Days KMS waits before deleting Vault's unseal key after a destroy."
  type        = number
  default     = 30
}

variable "vault_init_secret_recovery_window_in_days" {
  description = "Days Secrets Manager keeps the Vault init secret recoverable after a destroy. 0 deletes immediately."
  type        = number
  default     = 30
}
