locals {
  environment = "staging"
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
}
