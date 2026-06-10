locals {
  name_prefix = "hashi-platform"

  # Stable for_each keys for every per-AZ resource.
  azs = keys(var.public_subnet_cidrs)

  # Which NAT gateway each AZ's private route table points at.
  nat_azs            = var.nat_gateway_strategy == "per_az" ? local.azs : [local.azs[0]]
  nat_gateway_for_az = { for az in local.azs : az => var.nat_gateway_strategy == "per_az" ? az : local.azs[0] }

  # Cloud auto-join: Consul/Nomad agents discover their servers by this EC2
  # tag (e.g. `retry_join = "provider=aws tag_key=auto-join tag_value=hashi-platform-consul"`).
  # Layers 4 and 5 must tag their ASG instances with exactly these values.
  auto_join = {
    tag_key      = "auto-join"
    consul_value = "${local.name_prefix}-consul"
    nomad_value  = "${local.name_prefix}-nomad"
  }

  # Node roles that get an instance role + profile; the first three run
  # Consul/Nomad agents and need the auto-join policy.
  node_roles      = ["consul-server", "nomad-server", "nomad-client", "boundary-worker"]
  auto_join_roles = ["consul-server", "nomad-server", "nomad-client"]
}
