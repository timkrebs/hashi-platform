# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = nonsensitive(data.vault_kv_secret_v2.eks.data["region"])

  default_tags {
    tags = local.common_tags
  }
}

# Retained only so Terraform can destroy the previously-failed boundary-worker
# Helm release left in state. The worker is now deployed out-of-band. Safe to
# remove this provider + data source once that destroy has applied.
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# Manages the Boundary credential store + SSH target. Empty defaults are fine
# when enable_boundary_ssh = false (the provider is never invoked).
provider "boundary" {
  addr                   = var.boundary_addr
  auth_method_id         = var.boundary_auth_method_id
  auth_method_login_name = var.boundary_login_name
  auth_method_password   = var.boundary_password
}
