#------------------------------------------------------------------------
# Hashi Platform: HCP Vault - Terraform Vault Provider
#
# Dev mode Vault server configuration
#------------------------------------------------------------------------

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "3.9.0"
    }
  }
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}
