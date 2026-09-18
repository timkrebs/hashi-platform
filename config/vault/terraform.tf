terraform {
  required_version = "~> 1.15.0"

  cloud {
    organization = "tim-krebs-org"

    workspaces {
      name = "hashi-platform-vault"
    }
  }

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
