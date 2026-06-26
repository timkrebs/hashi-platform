# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {
  cluster_name = "${data.vault_kv_secret_v2.eks.data["cluster_name"]}-${random_string.suffix.result}"

  common_tags = {
    Project     = "hashi-platform"
    Environment = "learn"
    ManagedBy   = "Terraform"
  }
}
