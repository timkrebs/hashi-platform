provider "hcp" {}

provider "tfe" {}

data "tfe_outputs" "vault_cluster" {
  organization = var.tfc_organization
  workspace    = "2-vault-cluster"
}

# Fresh 6-hour admin token minted at the start of every run — the "secret
# zero" for configuring Vault. The provider transparently regenerates it when
# a run finds it expired. Nothing longer-lived is ever stored.
resource "hcp_vault_cluster_admin_token" "provisioner" {
  cluster_id = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_cluster_id
}

provider "vault" {
  address   = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_private_endpoint_url
  namespace = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_namespace
  token     = hcp_vault_cluster_admin_token.provisioner.token
}
