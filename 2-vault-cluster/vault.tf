# Layer 1 owns the HVN, peering, and routes — this layer only places the
# Vault cluster inside that network (a layer never recreates resources owned
# by an earlier layer).
data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "1-network"
}

resource "hcp_vault_cluster" "main" {
  cluster_id = var.vault_cluster_id
  hvn_id     = data.tfe_outputs.network.nonsensitive_values.hvn_id
  tier       = var.tier

  # Locked decision: private endpoint only — Vault is reached on :8200 over
  # the HVN <-> VPC peering. Cloud provider and region are inherited from
  # the HVN, so they are not (and cannot be) set here.
  public_endpoint = false
}

# Deliberately NO hcp_vault_cluster_admin_token here: it is a 6-hour
# credential, and persisting it in this workspace's shared state would park
# a live secret where every workspace can read it. Layer 3 mints a fresh
# token at the start of each of its runs instead.
