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
  }

  # No backend block: this layer runs VCS-driven in the HCP Terraform
  # workspace `2-vault-cluster`, which owns the state.
}
