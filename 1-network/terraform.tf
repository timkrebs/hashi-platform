terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.95.0, < 1.0.0"
    }
  }

  # No backend block: this layer runs VCS-driven in the HCP Terraform
  # workspace `1-network`, which owns the state.
}
