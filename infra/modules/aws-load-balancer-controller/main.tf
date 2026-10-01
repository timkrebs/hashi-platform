# IAM role the controller assumes through IRSA. The upstream module ships the
# controller's IAM policy, so it stays in step with the chart version.
module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name                              = "${var.cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    cluster = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.service_account_name}"]
    }
  }

  tags = var.tags
}

# The IAM policy bundled with terraform-aws-modules/iam 5.39.0 predates the
# controller version this chart installs, so it is missing the listener
# attribute APIs that LBC 2.8+ calls on every reconcile. Without them the
# controller builds a correct model and then fails with AccessDenied on
# DescribeListenerAttributes, and every LoadBalancer service hangs on
# <pending> with no obvious cause.
#
# This closes the gap without dragging in the coordinated provider/module major
# upgrade; it can be dropped once the upstream module is bumped.
resource "aws_iam_policy" "listener_attributes" {
  name        = "${var.cluster_name}-alb-controller-listener-attributes"
  description = "Listener attribute APIs the bundled load balancer controller policy is missing."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ListenerAttributes"
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:DescribeListenerAttributes",
        "elasticloadbalancing:ModifyListenerAttributes",
      ]
      Resource = "*"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "listener_attributes" {
  role       = module.irsa.iam_role_name
  policy_arn = aws_iam_policy.listener_attributes.arn
}

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = var.replica_count

    serviceAccount = {
      create = true
      name   = var.service_account_name
      annotations = {
        "eks.amazonaws.com/role-arn" = module.irsa.iam_role_arn
      }
    }

    resources = {
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
    }
  })]

  wait    = true
  timeout = 300
}
