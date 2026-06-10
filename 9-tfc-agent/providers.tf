provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project = local.name_prefix
      layer   = "1-tfc-agent"
      owner   = var.owner
      managed = "terraform"
    }
  }
}

provider "tfe" {}
