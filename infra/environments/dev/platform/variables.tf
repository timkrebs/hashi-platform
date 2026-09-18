variable "region" {
  description = "AWS region the environment is deployed to."
  type        = string
  default     = "us-east-1"
}

variable "enable_cert_manager" {
  description = "Install cert-manager, the issuer for in-cluster TLS certificates."
  type        = bool
  default     = true
}

variable "enable_checkmk" {
  description = "Create the Checkmk monitoring server on EC2."
  type        = bool
  default     = true
}

variable "checkmk_instance_type" {
  description = "EC2 instance type for the Checkmk server. The restrict-compute-size policy caps this at medium."
  type        = string
  default     = "t3.medium"
}

variable "checkmk_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Checkmk web interface. Defaults to the whole internet, and the certificate is self-signed, so narrow this where you can."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_argocd" {
  description = "Install Argo CD. Its Applications are not managed here: apply gitops/bootstrap/root-app.yaml once, then everything under gitops/apps is reconciled from Git."
  type        = bool
  default     = true
}

variable "enable_vault_prerequisites" {
  description = "Create the AWS resources Vault needs before it can start: the KMS auto-unseal key, the IRSA roles, the Secrets Manager secret for the init output, and the namespace and service accounts carrying the role annotations."
  type        = bool
  default     = true
}

variable "vault_namespace" {
  description = "Namespace Vault runs in. Must match the destination namespace of the Vault Application in gitops/apps."
  type        = string
  default     = "vault"
}

variable "vault_service_account" {
  description = "Service account the Vault server runs as. Must match server.serviceAccount.name in the Helm values."
  type        = string
  default     = "vault"
}

variable "vault_init_service_account" {
  description = "Service account the one-off init job runs as. It may write the init output to Secrets Manager; the server may not."
  type        = string
  default     = "vault-init"
}

variable "vault_kms_key_deletion_window_in_days" {
  description = "Days KMS waits before deleting Vault's unseal key after a destroy."
  type        = number
  default     = 30

  validation {
    condition     = var.vault_kms_key_deletion_window_in_days >= 7 && var.vault_kms_key_deletion_window_in_days <= 30
    error_message = "vault_kms_key_deletion_window_in_days must be between 7 and 30; AWS rejects anything outside that range."
  }
}

variable "vault_init_secret_recovery_window_in_days" {
  description = "Days Secrets Manager keeps the Vault init secret recoverable after a destroy. 0 deletes it immediately, so a rebuilt environment can reuse the name."
  type        = number
  default     = 30

  validation {
    condition     = var.vault_init_secret_recovery_window_in_days == 0 || (var.vault_init_secret_recovery_window_in_days >= 7 && var.vault_init_secret_recovery_window_in_days <= 30)
    error_message = "vault_init_secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "create_default_storage_class" {
  description = "Create an encrypted gp3 StorageClass backed by the EBS CSI driver and mark it default. The gp2 class EKS ships uses the in-tree provisioner that Kubernetes removed in 1.31, so without this nothing with a PersistentVolumeClaim can schedule."
  type        = bool
  default     = true
}

variable "argocd_service_type" {
  description = "Service type for the Argo CD UI. LoadBalancer puts an internet-facing NLB in front of it; ClusterIP keeps it behind port-forward."
  type        = string
  default     = "LoadBalancer"
}

variable "argocd_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Argo CD UI. Defaults to the whole internet, which is worth narrowing: Argo CD can deploy anything into the cluster."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_log_shipping" {
  description = "Ship container logs to CloudWatch Logs with Fluent Bit. Checkmk handles metrics and state; it is not a log store, so the logs go where they can be searched."
  type        = bool
  default     = true
}

variable "logging_namespace" {
  description = "Namespace Fluent Bit runs in. Must match the destination namespace of its Application in gitops/apps."
  type        = string
  default     = "logging"
}

variable "logging_service_account" {
  description = "Service account Fluent Bit runs as. Must match serviceAccount.name in the Helm values."
  type        = string
  default     = "aws-for-fluent-bit"
}

variable "log_retention_in_days" {
  description = "How long CloudWatch keeps the container logs."
  type        = number
  default     = 14
}
