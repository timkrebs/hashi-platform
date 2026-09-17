# Platform layer: the in-cluster add-ons that have to exist before workloads
# are deployed, plus the AWS resources they need. Secrets are served by HCP
# Vault Dedicated, which lives outside this configuration.

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
