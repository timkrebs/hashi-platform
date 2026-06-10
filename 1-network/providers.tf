# Both providers authenticate through the workspace's OIDC dynamic
# credentials (TFC_AWS_* / TFC_HCP_* env vars set by 0-bootstrap).
# The HCP project is inferred from the project-scoped service principal.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project = local.name_prefix
      layer   = "1-network"
      owner   = var.owner
      managed = "terraform"
    }
  }
}

provider "hcp" {}
