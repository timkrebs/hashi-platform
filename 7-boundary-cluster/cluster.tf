locals {
  name_prefix = "hashi-platform"
}

# Split out from the Boundary configuration layer (7-boundary) so the
# `boundary` provider there can target an ALREADY-EXISTING cluster. A provider
# cannot reliably authenticate against a resource created in the same run — the
# cluster URL is unknown at plan time and the provider falls back to
# 127.0.0.1:9200. Creating the cluster in its own workspace removes that
# chicken-and-egg dependency.
resource "hcp_boundary_cluster" "main" {
  cluster_id = local.name_prefix
  tier       = var.boundary_tier
  username   = var.boundary_admin_username
  password   = var.boundary_admin_password

  # No maintenance_window_config: that block is only valid for the SCHEDULED
  # upgrade type (it implicitly carries a `day`). Omitting it keeps the cluster
  # on the default AUTOMATIC upgrade cadence.
}
