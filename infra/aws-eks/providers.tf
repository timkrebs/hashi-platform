# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = nonsensitive(data.vault_kv_secret_v2.eks.data["region"])

  default_tags {
    tags = local.common_tags
  }
}

# Short-lived token to authenticate the Helm provider to the EKS API. Uses the
# AWS provider's STS (no aws CLI needed), so it works in HCP Terraform runs.
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Deploys the Boundary worker chart into the cluster. The Helm provider connects
# lazily, so it is a no-op when enable_boundary_ssh = false.
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
