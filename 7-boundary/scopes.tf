locals {
  name_prefix = "hashi-platform"

  # The worker config wants the cluster UUID, which only exists as the host
  # prefix of cluster_url (https://<uuid>.boundary.hashicorp.cloud). The cluster
  # now lives in 7-boundary-cluster, so derive it from that layer's output.
  boundary_cluster_uuid = data.tfe_outputs.boundary_cluster.nonsensitive_values.cluster_uuid

  # EC2 instances carrying this tag are discovered by the dynamic host
  # catalog and become Boundary hosts automatically.
  target_tag_key   = "boundary-target"
  target_tag_value = "ssh"
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
