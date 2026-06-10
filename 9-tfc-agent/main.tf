locals {
  name_prefix = "hashi-platform"
}

data "tfe_outputs" "network" {
  organization = var.tfc_organization
  workspace    = "1-network"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Outbound-only: the agent dials HCP Terraform (443), releases.hashicorp.com,
# AWS APIs, and the private Vault/Consul/Nomad endpoints. Nothing dials in.
resource "aws_security_group" "agent" {
  name        = "${local.name_prefix}-tfc-agent"
  description = "HCP Terraform agent - outbound only"
  vpc_id      = data.tfe_outputs.network.nonsensitive_values.vpc_id

  tags = {
    Name = "${local.name_prefix}-tfc-agent"
  }
}

resource "aws_vpc_security_group_egress_rule" "agent_all_outbound" {
  security_group_id = aws_security_group.agent.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound (TFC API, provider registries, private endpoints)"

  tags = {
    Name = "tfc-agent-all-outbound"
  }
}

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

data "aws_iam_policy_document" "read_agent_token" {
  statement {
    sid       = "ReadAgentToken"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.agent_token_ssm_parameter}"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "agent" {
  name               = "${local.name_prefix}-tfc-agent"
  description        = "Instance role for the HCP Terraform agent"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "read_agent_token" {
  name   = "read-agent-token"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.read_agent_token.json
}

# Break-glass ops access (SSM Session Manager) until Boundary owns human
# access end-to-end; the no-SSH posture stays intact.
resource "aws_iam_role_policy_attachment" "agent_ssm_core" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "agent" {
  name = "${local.name_prefix}-tfc-agent"
  role = aws_iam_role.agent.name
}

resource "aws_launch_template" "agent" {
  name          = "${local.name_prefix}-tfc-agent"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.agent.name
  }

  vpc_security_group_ids = [aws_security_group.agent.id]

  user_data = base64encode(templatefile("${path.module}/templates/agent-userdata.sh.tpl", {
    ssm_parameter_name = var.agent_token_ssm_parameter
    region             = var.aws_region
    version            = var.tfc_agent_version
  }))

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${local.name_prefix}-tfc-agent"
    }
  }
}

# ASG of one: not for scale, for self-healing — a replaced instance re-reads
# the token from SSM and re-registers with the pool on its own.
resource "aws_autoscaling_group" "agent" {
  name                = "${local.name_prefix}-tfc-agent"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = values(data.tfe_outputs.network.nonsensitive_values.private_subnet_ids)

  launch_template {
    id      = aws_launch_template.agent.id
    version = aws_launch_template.agent.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-tfc-agent"
    propagate_at_launch = true
  }
}
