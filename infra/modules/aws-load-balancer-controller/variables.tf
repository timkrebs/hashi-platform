variable "cluster_name" {
  description = "Name of the EKS cluster the controller manages load balancers for. Also prefixes the IAM role name."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,39}$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters of letters, digits, hyphens and underscores."
  }
}

variable "region" {
  description = "AWS region of the cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in; the controller discovers subnets and creates security groups here."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider, used for the controller's IRSA trust policy."
  type        = string
}

variable "chart_version" {
  description = "Version of the eks/aws-load-balancer-controller Helm chart."
  type        = string
  default     = "3.5.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be an exact semantic version such as 3.5.0."
  }
}

variable "namespace" {
  description = "Namespace the controller is installed into. Must already exist."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the controller's service account; bound to the IRSA role."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "replica_count" {
  description = "Controller replicas. One is enough for small clusters; use two for production."
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 1 && floor(var.replica_count) == var.replica_count
    error_message = "replica_count must be a whole number of at least 1."
  }
}

variable "tags" {
  description = "Tags applied to the IAM resources created by this module."
  type        = map(string)
  default     = {}
}
