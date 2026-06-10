# Dynamic AWS host catalog: targets are discovered by EC2 tag, never
# hand-listed. The HCP-hosted plugin needs AWS credentials; this is the one
# documented static-credential exception in the platform — a dedicated IAM
# user that can do nothing but DescribeInstances. Rotation is disabled
# because Boundary-managed rotation deletes any Terraform-managed key and
# the two systems then fight (the plugin's own guidance for IaC-managed keys).

resource "aws_iam_user" "host_catalog" {
  name = "${local.name_prefix}-boundary-host-catalog"
}

data "aws_iam_policy_document" "describe_instances" {
  statement {
    sid       = "BoundaryHostDiscovery"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "host_catalog" {
  name   = "describe-instances"
  user   = aws_iam_user.host_catalog.name
  policy = data.aws_iam_policy_document.describe_instances.json
}

resource "aws_iam_access_key" "host_catalog" {
  user = aws_iam_user.host_catalog.name
}

resource "boundary_host_catalog_plugin" "aws" {
  name        = "aws-ec2"
  description = "Dynamic EC2 host discovery by tag"
  scope_id    = boundary_scope.platform.id
  plugin_name = "aws"

  attributes_json = jsonencode({
    region                      = var.aws_region
    disable_credential_rotation = true
  })

  secrets_json = jsonencode({
    access_key_id     = aws_iam_access_key.host_catalog.id
    secret_access_key = aws_iam_access_key.host_catalog.secret
  })
}

resource "boundary_host_set_plugin" "ssh_targets" {
  name            = "ssh-targets"
  description     = "Every instance tagged ${local.target_tag_key}=${local.target_tag_value}"
  host_catalog_id = boundary_host_catalog_plugin.aws.id

  attributes_json = jsonencode({
    filters = ["tag:${local.target_tag_key}=${local.target_tag_value}"]
  })
}
