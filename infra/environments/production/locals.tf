locals {
  environment = "production"
  project     = "hashi-platform"

  # Naming convention shared by every environment: <project>-<environment>-cluster.
  cluster_name = "${local.project}-${local.environment}-cluster"

  common_tags = {
    Environment = title(local.environment)
    Project     = local.project
    ManagedBy   = "Terraform"
  }
}
