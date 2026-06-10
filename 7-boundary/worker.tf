# Self-managed egress worker: outbound-only EC2 in a private subnet. It dials
# the HCP-managed ingress workers (9202) and proxies sessions to private
# targets; it also fronts Boundary's Vault calls (credential store
# worker_filter), since the control plane cannot reach the private Vault.

# Controller-led registration: this resource issues a one-time activation
# token the instance presents at first boot. To replace the instance, taint
# this resource too — a used activation token cannot re-register a fresh node.
resource "boundary_worker" "egress" {
  scope_id    = "global"
  name        = "${local.name_prefix}-egress"
  description = "Self-managed egress worker (private subnet, outbound only)"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "egress_worker" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.worker_instance_type
  subnet_id     = data.tfe_outputs.network.nonsensitive_values.private_subnet_ids["a"]

  vpc_security_group_ids = [data.tfe_outputs.network.nonsensitive_values.security_group_ids["boundary-worker"]]
  iam_instance_profile   = data.tfe_outputs.network.nonsensitive_values.instance_profile_names["boundary-worker"]

  user_data = templatefile("${path.module}/templates/worker-userdata.sh.tpl", {
    boundary_cluster_uuid = local.boundary_cluster_uuid
    activation_token      = boundary_worker.egress.controller_generated_activation_token
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.name_prefix}-boundary-egress-worker"
  }
}
