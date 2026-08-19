# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
  default     = "hp-dev-euc1-vpc"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "hp-dev-euc1-eks"
}
