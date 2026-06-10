# Consumed by Layer 3 (vault provider address/namespace) and Layer 7
# (Boundary credential store) via the `tfe_outputs` data source.

output "vault_cluster_id" {
  description = "HCP Vault Dedicated cluster ID — Layer 3 mints its per-run admin token against this"
  value       = hcp_vault_cluster.main.cluster_id
}

output "vault_namespace" {
  description = "Root namespace of the cluster (admin on HCP Vault Dedicated)"
  value       = hcp_vault_cluster.main.namespace
}

output "vault_private_endpoint_url" {
  description = "Private Vault API address, reachable only over the HVN peering"
  value       = hcp_vault_cluster.main.vault_private_endpoint_url
}
