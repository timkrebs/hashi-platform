terraform {
  required_version = "~> 1.15.0"

  cloud {
    organization = "tim-krebs-org"

    workspaces {
      name = "hashi-platform-dev-platform"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.47.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}
