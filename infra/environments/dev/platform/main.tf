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
