terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    boundary = {
      source  = "hashicorp/boundary"
      version = "~> 1.1"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.95.0, < 1.0.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.65"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }

  # No backend block: runs VCS-driven in workspace `7-boundary` in AGENT mode
  # — the vault provider must reach the private Vault endpoint to mint the
  # credential-store token.
}
