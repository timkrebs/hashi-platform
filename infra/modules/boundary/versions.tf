terraform {
  required_version = ">= 1.9.0"

  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.100.0, < 1.0.0"
    }
  }
}
