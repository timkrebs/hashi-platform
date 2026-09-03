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

  # What Argo CD reconciles for this environment: its own branch, its own
  # directory. The repository is public, so no credentials are involved.
  gitops_repo_url = "https://github.com/timkrebs/hashi-platform.git"
  gitops_revision = local.environment
  gitops_path     = "gitops/clusters/${local.environment}"

  # Terraform -> GitOps bridge. ApplicationSets read these annotations from
  # the in-cluster secret, so Helm values never hard-code account-specific
  # identifiers in the repository.
  cluster_secret_annotations = {
    "hashi-platform.io/environment"              = local.environment
    "hashi-platform.io/region"                   = var.region
    "hashi-platform.io/account-id"               = data.aws_caller_identity.current.account_id
    "hashi-platform.io/cluster-name"             = local.cluster_name
    "hashi-platform.io/vault-kms-key-alias"      = module.vault_prerequisites.kms_key_alias
    "hashi-platform.io/vault-kms-key-arn"        = module.vault_prerequisites.kms_key_arn
    "hashi-platform.io/vault-irsa-role-arn"      = module.vault_prerequisites.vault_irsa_role_arn
    "hashi-platform.io/vault-init-irsa-role-arn" = module.vault_prerequisites.vault_init_irsa_role_arn
    "hashi-platform.io/vault-init-secret-name"   = module.vault_prerequisites.init_secret_name
    # Helm list syntax, consumed as --set publicService.loadBalancerSourceRanges={...}
    "hashi-platform.io/vault-allowed-cidrs" = "{${join(",", var.vault_allowed_cidrs)}}"
  }
}
