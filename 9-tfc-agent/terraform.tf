terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.65"
    }
  }

  # No backend block: this layer runs VCS-driven in the HCP Terraform
  # workspace `1-tfc-agent` (remote mode — it only calls public AWS APIs;
  # the agent it creates is what lets *other* layers reach private endpoints).
}
