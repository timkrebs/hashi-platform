terraform {
  required_version = ">= 1.9.0"

  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.95.0, < 1.0.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.65"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }

  # No backend block: runs VCS-driven in workspace `3-vault-config`, which
  # executes in AGENT mode (the vault provider talks to the private endpoint,
  # reachable only from inside the VPC).
}
