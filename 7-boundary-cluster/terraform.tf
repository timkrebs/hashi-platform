terraform {
  required_version = ">= 1.9.0"

  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.95.0, < 1.0.0"
    }
  }

  # No backend block: runs VCS-driven in workspace `7-boundary-cluster` in
  # REMOTE mode — provisioning the HCP Boundary cluster only touches the public
  # HCP control plane, so no in-VPC agent is required.
}
