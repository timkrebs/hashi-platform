terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.47.0, < 6.64.1"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
}
