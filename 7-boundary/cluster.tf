locals {
  name_prefix = "hashi-platform"

  # The worker config wants the cluster UUID, which only exists as the host
  # prefix of cluster_url (https://<uuid>.boundary.hashicorp.cloud).
  boundary_cluster_uuid = regex("^https://([0-9a-f-]+)\\.", hcp_boundary_cluster.main.cluster_url)[0]

  # EC2 instances carrying this tag are discovered by the dynamic host
  # catalog and become Boundary hosts automatically.
  target_tag_key   = "boundary-target"
  target_tag_value = "ssh"
}

resource "hcp_boundary_cluster" "main" {
  cluster_id = local.name_prefix
  tier       = var.boundary_tier
  username   = var.boundary_admin_username
  password   = var.boundary_admin_password

  maintenance_window_config {
    upgrade_type = "AUTOMATIC"
  }
}

# Scopes mirror intended team boundaries (org -> project), per the reference
# architecture. auto_create_admin_role keeps the bootstrapping admin able to
# manage the new scopes.
resource "boundary_scope" "org" {
  name                     = local.name_prefix
  description              = "hashi-platform organization scope"
  scope_id                 = "global"
  auto_create_admin_role   = true
  auto_create_default_role = true
}

resource "boundary_scope" "platform" {
  name                   = "platform"
  description            = "AWS platform infrastructure (Consul, Nomad, workloads)"
  scope_id               = boundary_scope.org.id
  auto_create_admin_role = true
}
