# Ships container logs to CloudWatch Logs. Checkmk is a monitoring system, not
# a log store: it can alert on patterns in a file an agent can read, but it
# offers no searchable log history. Keeping the logs in CloudWatch and the
# metrics in Checkmk plays to what each one is actually good at.

# Created here, not by Fluent Bit's auto-create, so the retention is explicit.
# An auto-created group keeps everything forever and bills for it.
resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = var.retention_in_days

  tags = var.tags
}

# jsonencode rather than an aws_iam_policy_document data source: under a mocked
# provider the data source returns a mock instead of rendering, so the policy
# could not be asserted on in the unit tests.
locals {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteContainerLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = [
        aws_cloudwatch_log_group.this.arn,
        "${aws_cloudwatch_log_group.this.arn}:*",
      ]
      # Deliberately no logs:CreateLogGroup: the group belongs to Terraform, and
      # without that permission a misconfigured output cannot silently create a
      # second one with no retention.
    }]
  })
}

resource "aws_iam_policy" "this" {
  name        = "${var.cluster_name}-fluent-bit"
  description = "Lets Fluent Bit write container logs into its own CloudWatch log group."
  policy      = local.policy

  tags = var.tags
}

module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "${var.cluster_name}-fluent-bit"
  role_policy_arns = {
    logs = aws_iam_policy.this.arn
  }

  oidc_providers = {
    cluster = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.service_account_name}"]
    }
  }

  tags = var.tags
}
