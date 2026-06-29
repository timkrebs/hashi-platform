# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = nonsensitive(data.vault_kv_secret_v2.eks.data["region"])

  default_tags {
    tags = local.common_tags
  }
}

# Manages the Boundary credential store + SSH target. Empty defaults are fine
# when enable_boundary_ssh = false (the provider is never invoked).
provider "boundary" {
  addr                            = var.boundary_addr
  auth_method_id                  = var.boundary_auth_method_id
  password_auth_method_login_name = var.boundary_login_name
  password_auth_method_password   = var.boundary_password
}
