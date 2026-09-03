# Platform layer: everything that must exist inside the cluster before Argo CD
# can take over, plus the AWS resources Vault depends on. Workloads themselves
# (Vault, later Boundary workers) are reconciled by Argo CD from gitops/.

module "aws_load_balancer_controller" {
  source = "../../../modules/aws-load-balancer-controller"

  cluster_name      = local.cluster_name
  region            = var.region
  vpc_id            = local.cluster.vpc_id
  oidc_provider_arn = local.cluster.oidc_provider_arn

  tags = local.common_tags
}

module "cert_manager" {
  count  = var.enable_cert_manager ? 1 : 0
  source = "../../../modules/cert-manager"
}

module "vault_prerequisites" {
  source = "../../../modules/vault-aws-prerequisites"

  name_prefix      = "${local.project}-${local.environment}"
  oidc_provider    = local.cluster.oidc_provider
  init_secret_name = "${local.project}/${local.environment}/vault/init"

  kms_key_deletion_window_in_days = var.vault_kms_key_deletion_window_in_days
  secret_recovery_window_in_days  = var.vault_init_secret_recovery_window_in_days

  tags = local.common_tags
}

module "argocd" {
  source = "../../../modules/argocd"

  cluster_secret_labels = {
    "hashi-platform.io/environment" = local.environment
  }
  cluster_secret_annotations = local.cluster_secret_annotations
}

module "argocd_root_app" {
  source = "../../../modules/argocd-root-app"

  namespace       = module.argocd.namespace
  repo_url        = local.gitops_repo_url
  target_revision = local.gitops_revision
  path            = local.gitops_path

  # Destroy order: Argo CD must remove every workload it manages (and the
  # load balancers and volumes they created) before the controllers those
  # workloads rely on are uninstalled. Terraform destroys in reverse
  # dependency order, so the root Application goes first.
  depends_on = [
    module.argocd,
    module.aws_load_balancer_controller,
    module.cert_manager,
    module.vault_prerequisites,
  ]
}
