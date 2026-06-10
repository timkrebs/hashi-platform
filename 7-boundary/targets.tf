resource "boundary_target" "private_ssh" {
  name        = "private-ssh"
  description = "SSH to any instance tagged ${local.target_tag_key}=${local.target_tag_value}, credentials injected from Vault"
  scope_id    = boundary_scope.platform.id

  type         = "ssh"
  default_port = 22

  host_source_ids = [boundary_host_set_plugin.ssh_targets.id]
  injected_application_credential_source_ids = [
    boundary_credential_library_vault_ssh_certificate.ssh_cert.id,
  ]

  # Sessions must traverse the self-managed worker — it is the only thing
  # with a network path to the private subnets.
  egress_worker_filter     = "\"egress\" in \"/tags/type\""
  session_connection_limit = -1
}

# --- Throwaway demo target (enable_demo_target) -----------------------------
# Proves the chain end-to-end before Layers 4-6 provide real targets. Its SG
# lives here (not Layer 1) because it is ephemeral by design.

resource "aws_security_group" "demo_target" {
  count = var.enable_demo_target ? 1 : 0

  name        = "${local.name_prefix}-demo-target"
  description = "Throwaway Boundary demo target - SSH from the egress worker only"
  vpc_id      = data.tfe_outputs.network.nonsensitive_values.vpc_id

  tags = {
    Name = "${local.name_prefix}-demo-target"
  }
}

resource "aws_vpc_security_group_ingress_rule" "demo_target_ssh" {
  count = var.enable_demo_target ? 1 : 0

  security_group_id            = aws_security_group.demo_target[0].id
  referenced_security_group_id = data.tfe_outputs.network.nonsensitive_values.security_group_ids["boundary-worker"]
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  description                  = "SSH from the Boundary egress worker"

  tags = {
    Name = "demo-target-22-tcp-from-boundary-worker"
  }
}

resource "aws_vpc_security_group_egress_rule" "demo_target_all_outbound" {
  count = var.enable_demo_target ? 1 : 0

  security_group_id = aws_security_group.demo_target[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound (Vault CA fetch over peering, packages via NAT)"

  tags = {
    Name = "demo-target-all-outbound"
  }
}

resource "aws_instance" "demo_target" {
  count = var.enable_demo_target ? 1 : 0

  ami           = data.aws_ami.al2023.id
  instance_type = var.demo_target_instance_type
  subnet_id     = data.tfe_outputs.network.nonsensitive_values.private_subnet_ids["b"]

  vpc_security_group_ids = [aws_security_group.demo_target[0].id]

  user_data = templatefile("${path.module}/templates/demo-target-userdata.sh.tpl", {
    vault_addr     = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_private_endpoint_url
    ssh_mount_path = data.tfe_outputs.vault_config.nonsensitive_values.ssh_mount_path
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
    Name                   = "${local.name_prefix}-demo-target"
    (local.target_tag_key) = local.target_tag_value
  }
}
