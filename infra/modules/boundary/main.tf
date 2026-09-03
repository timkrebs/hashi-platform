# Placeholder for the access layer. Today it can create the HCP Boundary
# control plane and nothing else; workers, targets and the Vault credential
# store are documented in README.md and land once Vault is running.
resource "hcp_boundary_cluster" "this" {
  count = var.enabled ? 1 : 0

  cluster_id = var.cluster_id
  tier       = var.tier
  username   = var.admin_username
  password   = var.admin_password
}
