variable "cluster_name" {
  description = "Name of the EKS cluster whose logs are shipped. Prefixes the IAM role name."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,39}$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters of letters, digits, hyphens and underscores."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider, for the IRSA trust policy."
  type        = string
}

variable "namespace" {
  description = "Namespace Fluent Bit runs in."
  type        = string
  default     = "logging"
}

variable "service_account_name" {
  description = "Service account Fluent Bit runs as. It must match serviceAccount.name in the Helm values."
  type        = string
  default     = "aws-for-fluent-bit"
}

variable "log_group_name" {
  description = "CloudWatch log group the container logs are written to."
  type        = string
  default     = "/aws/eks/hashi-platform-dev/containers"
}

variable "retention_in_days" {
  description = "How long CloudWatch keeps the logs. Created here rather than letting Fluent Bit auto-create the group, because an auto-created group never expires and bills forever."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days must be one of the values CloudWatch accepts, for example 7, 14, 30 or 90."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
