# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "prefix" {
  description = "Fixed resource name prefix"
  type        = string
  default     = "hp"
}

variable "env" {
  description = "Environment (dev, stg, prd)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prd"], var.env)
    error_message = "env must be one of: dev, stg, prd."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = contains(["eu-central-1", "eu-north-1", "us-east-1"], var.region)
    error_message = "region must be one of: eu-central-1, eu-north-1, us-east-1."
  }
}
