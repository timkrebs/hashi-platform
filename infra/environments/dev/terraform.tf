terraform {
  required_version = "~> 1.15.0"

  cloud {
    organization = "tim-krebs-org"

    workspaces {
      name = "hashi-platform-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.47.0"
    }

    # Used transitively by terraform-aws-modules/eks. Pinned here so the root
    # lock file controls their versions.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.5"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3.4"
    }

    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}
