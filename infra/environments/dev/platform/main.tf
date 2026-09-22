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

module "argocd" {
  count  = var.enable_argocd ? 1 : 0
  source = "../../../modules/argocd"

  cluster_secret_labels = {
    "hashi-platform.io/environment" = local.environment
  }

  service_type                = var.argocd_service_type
  load_balancer_source_ranges = var.argocd_allowed_cidr_blocks
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

# EKS ships a legacy gp2 class backed by the in-tree provisioner
# kubernetes.io/aws-ebs, which Kubernetes removed in 1.31 -- on 1.35 it
# provisions nothing. The aws-ebs-csi-driver addon brings no StorageClass of its
# own, so without this every PersistentVolumeClaim stays Pending and anything
# with state (Vault's raft and audit volumes) never schedules.
resource "kubernetes_storage_class_v1" "gp3" {
  count = var.create_default_storage_class ? 1 : 0

  metadata {
    name = "gp3"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  # Bind only once a pod is scheduled, so the volume lands in the same zone.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# A durable copy of the container logs, outside the cluster. Interactive search
# runs on Loki inside it, which goes away when the environment does; this is the
# copy that does not.
module "fluent_bit" {
  count  = var.enable_log_shipping ? 1 : 0
  source = "../../../modules/aws-fluent-bit-cloudwatch"

  cluster_name      = local.cluster_name
  oidc_provider_arn = local.cluster.oidc_provider_arn

  namespace            = var.logging_namespace
  service_account_name = var.logging_service_account
  log_group_name       = "/aws/eks/${local.cluster_name}/containers"
  retention_in_days    = var.log_retention_in_days

  tags = local.common_tags
}

# Same reason as the Vault service account: the IRSA annotation carries the AWS
# account ID, which must not land in this public repository, so the chart is
# told to reuse what Terraform created.
resource "kubernetes_namespace_v1" "logging" {
  count = var.enable_log_shipping ? 1 : 0

  metadata {
    name = var.logging_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_service_account_v1" "fluent_bit" {
  count = var.enable_log_shipping ? 1 : 0

  metadata {
    name      = var.logging_service_account
    namespace = one(kubernetes_namespace_v1.logging[*].metadata[0].name)

    annotations = {
      "eks.amazonaws.com/role-arn" = one(module.fluent_bit[*].iam_role_arn)
    }
  }
}
