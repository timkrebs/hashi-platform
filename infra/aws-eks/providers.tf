# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = data.vault_kv_secret_v2.eks.data["region"]

  default_tags {
    tags = local.common_tags
  }
}
