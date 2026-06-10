# Scoped instance roles/profiles per node role. Layers 4-7 attach further
# least-privilege policies (e.g. S3 snapshots in Layer 8) to these roles.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  for_each = toset(local.node_roles)

  name               = "${local.name_prefix}-${each.key}"
  description        = "Instance role for ${each.key} nodes"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# ec2:DescribeInstances is the entire cloud auto-join surface; Describe*
# actions do not support resource-level scoping, hence the "*".
data "aws_iam_policy_document" "auto_join" {
  statement {
    sid       = "CloudAutoJoin"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "auto_join" {
  name        = "${local.name_prefix}-auto-join"
  description = "Read EC2 instance metadata/tags for Consul and Nomad cloud auto-join"
  policy      = data.aws_iam_policy_document.auto_join.json
}

resource "aws_iam_role_policy_attachment" "auto_join" {
  for_each = toset(local.auto_join_roles)

  role       = aws_iam_role.node[each.key].name
  policy_arn = aws_iam_policy.auto_join.arn
}

resource "aws_iam_instance_profile" "node" {
  for_each = toset(local.node_roles)

  name = "${local.name_prefix}-${each.key}"
  role = aws_iam_role.node[each.key].name
}
