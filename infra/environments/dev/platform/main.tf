# Platform layer: the in-cluster add-ons that have to exist before workloads
# are deployed, plus the AWS resources they need.
#
# Argo CD is installed here but its Applications are not: the root Application
# in gitops/bootstrap is applied once by hand, and from then on everything
# under gitops/apps is reconciled from Git. Vault itself is one of those
# Applications; Terraform only provides what it cannot create for itself --
# the KMS unseal key, the IRSA roles, and the service account carrying the
# role annotation.

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

# Checkmk monitoring. It only needs the VPC, but it lives here so it shares the
# add-ons' lifecycle and is torn down with them.
module "checkmk" {
  count  = var.enable_checkmk ? 1 : 0
  source = "../../../modules/aws-checkmk-server"

  name      = "${local.project}-${local.environment}-checkmk"
  region    = var.region
  vpc_id    = local.cluster.vpc_id
  subnet_id = local.checkmk_subnet_id

  instance_type       = var.checkmk_instance_type
  allowed_cidr_blocks = var.checkmk_allowed_cidr_blocks

  tags = local.common_tags
}

module "argocd" {
  count  = var.enable_argocd ? 1 : 0
  source = "../../../modules/argocd"

  cluster_secret_labels = {
    "hashi-platform.io/environment" = local.environment
  }
}

module "vault_prerequisites" {
  count  = var.enable_vault_prerequisites ? 1 : 0
  source = "../../../modules/vault-aws-prerequisites"

  name_prefix      = "${local.project}-${local.environment}"
  oidc_provider    = local.cluster.oidc_provider
  init_secret_name = "${local.project}/${local.environment}/vault/init"

  kms_key_deletion_window_in_days = var.vault_kms_key_deletion_window_in_days
  secret_recovery_window_in_days  = var.vault_init_secret_recovery_window_in_days

  tags = local.common_tags
}

# The namespace and service accounts are created here rather than by the Helm
# chart because the IRSA annotation carries the AWS account ID, which must not
# land in this public repository. The chart is told to reuse them through
# server.serviceAccount.create = false in gitops/values/vault/values.yaml.
resource "kubernetes_namespace_v1" "vault" {
  count = var.enable_vault_prerequisites ? 1 : 0

  metadata {
    name = var.vault_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_service_account_v1" "vault" {
  count = var.enable_vault_prerequisites ? 1 : 0

  metadata {
    name      = var.vault_service_account
    namespace = one(kubernetes_namespace_v1.vault[*].metadata[0].name)

    annotations = {
      "eks.amazonaws.com/role-arn" = one(module.vault_prerequisites[*].vault_irsa_role_arn)
    }
  }
}

# Used once by the init job that stores the recovery keys and root token in
# Secrets Manager; kept separate so the server never holds write access to them.
resource "kubernetes_service_account_v1" "vault_init" {
  count = var.enable_vault_prerequisites ? 1 : 0

  metadata {
    name      = var.vault_init_service_account
    namespace = one(kubernetes_namespace_v1.vault[*].metadata[0].name)

    annotations = {
      "eks.amazonaws.com/role-arn" = one(module.vault_prerequisites[*].vault_init_irsa_role_arn)
    }
  }
}
