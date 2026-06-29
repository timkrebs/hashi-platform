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

# --- Boundary SSH automation --------------------------------------------------
# Generates an SSH key, stores it in Vault, and creates a Boundary SSH target on
# apply. See docs/boundary-vault-credential-store.md (Appendix B) for the
# prerequisites (Vault write policy, Boundary admin creds, an in-cluster worker).

variable "enable_boundary_ssh" {
  description = "Generate an SSH key, store it in Vault, and create a Boundary SSH target for the nodes."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name used in Boundary/Vault resource names (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "ssh_username" {
  description = "SSH login user on the nodes (AL2023 default is ec2-user)."
  type        = string
  default     = "ec2-user"
}

variable "ssh_target_address" {
  description = "Address the Boundary SSH target points at (a bastion or node IP reachable from the worker)."
  type        = string
  default     = ""
}

variable "boundary_addr" {
  description = "HCP Boundary cluster address, e.g. https://<id>.boundary.hashicorp.cloud."
  type        = string
  default     = ""
}

variable "boundary_auth_method_id" {
  description = "Boundary password auth method ID (ampw_...) Terraform uses to authenticate."
  type        = string
  default     = ""
}

variable "boundary_login_name" {
  description = "Boundary admin login name used by Terraform."
  type        = string
  default     = ""
}

variable "boundary_password" {
  description = "Boundary admin password used by Terraform."
  type        = string
  default     = ""
  sensitive   = true
}

variable "boundary_project_id" {
  description = "Existing Boundary project scope ID (p_...) where the SSH target is created."
  type        = string
  default     = ""
}

variable "boundary_vault_address" {
  description = "Vault address the Boundary cluster uses to reach Vault (public HCP Vault URL)."
  type        = string
  default     = ""
}

variable "boundary_vault_namespace" {
  description = "Vault namespace for the Boundary credential store."
  type        = string
  default     = "admin/hcp-platform"
}

variable "boundary_cred_store_token" {
  description = "Periodic, orphan, renewable Vault token for the Boundary credential store (from runbook Part A.4)."
  type        = string
  default     = ""
  sensitive   = true
}
