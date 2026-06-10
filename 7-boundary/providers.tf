provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project = local.name_prefix
      layer   = "7-boundary"
      owner   = var.owner
      managed = "terraform"
    }
  }
}

provider "hcp" {}

provider "tfe" {}

data "tfe_outputs" "boundary_cluster" {
  organization = var.tfc_organization
  workspace    = "7-boundary-cluster"
}

data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "1-network"
}

data "tfe_outputs" "vault_cluster" {
  organization = var.tfc_organization
  workspace    = "2-vault-cluster"
}

data "tfe_outputs" "vault_config" {
  organization = var.tfc_organization
  workspace    = "3-vault-config"
}

# Bootstraps against the cluster created in 7-boundary-cluster; its URL is read
# from that layer's outputs, so the provider targets an already-existing
# cluster (no same-run chicken-and-egg). Discovers the primary (password) auth
# method automatically.
provider "boundary" {
  addr                   = data.tfe_outputs.boundary_cluster.nonsensitive_values.cluster_url
  auth_method_login_name = var.boundary_admin_username
  auth_method_password   = var.boundary_admin_password
}

# Same per-run pattern as Layer 3. Runs of layers 3 and 7 each mint their own
# short-lived admin token; avoid running both workspaces simultaneously.
resource "hcp_vault_cluster_admin_token" "provisioner" {
  cluster_id = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_cluster_id
}

provider "vault" {
  address   = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_private_endpoint_url
  namespace = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_namespace
  token     = hcp_vault_cluster_admin_token.provisioner.token
}
