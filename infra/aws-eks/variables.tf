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

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node groups. Set per workspace; Sentinel restricts the allowed values per environment."
  type        = list(string)
  default     = ["t3.small"]
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}
