locals {
  environment = "dev"
  project     = "hashi-platform"

  # Same naming convention as the cluster layer.
  cluster_name = "${local.project}-${local.environment}-cluster"

  common_tags = {
    Environment = title(local.environment)
    Project     = local.project
    ManagedBy   = "Terraform"
  }

  cluster                = data.terraform_remote_state.cluster.outputs
  cluster_ca_certificate = local.cluster.cluster_certificate_authority_data == null ? null : base64decode(local.cluster.cluster_certificate_authority_data)

  # Null until the cluster workspace has state. try() is required because
  # indexing a null value is an error, not a null.
  checkmk_subnet_id = try(local.cluster.public_subnet_ids[0], null)
}
