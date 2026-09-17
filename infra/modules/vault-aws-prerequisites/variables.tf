variable "name_prefix" {
  description = "Prefix for every resource name, typically <project>-<environment>. Also the default prefix of the init secret."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,49}$", var.name_prefix))
    error_message = "name_prefix must be 1-50 lowercase alphanumeric characters or hyphens, so derived IAM role names stay under 64 characters."
  }
}

variable "oidc_provider" {
  description = "OIDC issuer URL of the EKS cluster without the https:// prefix, as exported by the aws-eks-cluster module."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace Vault runs in."
  type        = string
  default     = "vault"
}

variable "service_account" {
  description = "Service account of the Vault server pods; allowed to use the unseal key."
  type        = string
  default     = "vault"
}

variable "init_service_account" {
  description = "Service account of the one-off init job; allowed to write the init secret."
  type        = string
  default     = "vault-init"
}

variable "init_secret_name" {
  description = "Name of the Secrets Manager secret that receives recovery keys, root token and CA from the init job. Defaults to <name_prefix>/vault/init."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "Days KMS waits before deleting the unseal key after destroy. 7 for ephemeral environments, 30 for production."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30 && floor(var.kms_key_deletion_window_in_days) == var.kms_key_deletion_window_in_days
    error_message = "kms_key_deletion_window_in_days must be a whole number between 7 and 30."
  }
}

variable "secret_recovery_window_in_days" {
  description = "Days Secrets Manager keeps the init secret recoverable after destroy. 0 deletes immediately so an ephemeral environment can be recreated under the same name; use 30 for production."
  type        = number
  default     = 30

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
