# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane and managed node groups"
  type        = string
  default     = "1.34"

  validation {
    condition     = tonumber(var.cluster_version) >= 1.33
    error_message = "Use Kubernetes 1.33 or newer; this config provisions AL2023 nodes, which require 1.33+."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}
