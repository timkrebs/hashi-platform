# Role-based security groups, referencing each other by SG ID (never by
# CIDR) — except the single deliberate CIDR rule from the HVN, below.
# Port matrix: reference-architecture.md §5.4.

resource "aws_security_group" "consul_server" {
  name        = "${local.name_prefix}-consul-server"
  description = "Consul servers - service catalog, mesh control plane, Connect CA"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-consul-server"
  }
}

resource "aws_security_group" "nomad_server" {
  name        = "${local.name_prefix}-nomad-server"
  description = "Nomad servers - scheduling, workload identity JWKS issuer"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-nomad-server"
  }
}

resource "aws_security_group" "nomad_client" {
  name        = "${local.name_prefix}-nomad-client"
  description = "Nomad clients - workload tier with Connect sidecars"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-nomad-client"
  }
}

resource "aws_security_group" "boundary_worker" {
  name        = "${local.name_prefix}-boundary-worker"
  description = "Boundary egress worker - outbound-only, no inbound rules"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-boundary-worker"
  }
}

locals {
  sg_ids = {
    consul-server   = aws_security_group.consul_server.id
    nomad-server    = aws_security_group.nomad_server.id
    nomad-client    = aws_security_group.nomad_client.id
    boundary-worker = aws_security_group.boundary_worker.id
  }

  # Every node in these SGs runs a Consul agent (gossip + RPC participant).
  cluster_members = ["consul-server", "nomad-server", "nomad-client"]

  # Boundary's egress worker proxies operators to the Consul/Nomad APIs (UI
  # access through Boundary in Layer 7), hence its presence on 8500/8501/4646.
  sg_rule_spec = [
    { to = "consul-server", port_from = 8300, port_to = 8300, protocols = ["tcp"], sources = local.cluster_members, desc = "Consul server RPC" },
    { to = "consul-server", port_from = 8301, port_to = 8301, protocols = ["tcp", "udp"], sources = local.cluster_members, desc = "Consul Serf LAN gossip" },
    { to = "consul-server", port_from = 8302, port_to = 8302, protocols = ["tcp", "udp"], sources = ["consul-server"], desc = "Consul Serf WAN gossip (server-to-server)" },
    { to = "consul-server", port_from = 8500, port_to = 8500, protocols = ["tcp"], sources = concat(local.cluster_members, ["boundary-worker"]), desc = "Consul HTTP API/UI" },
    { to = "consul-server", port_from = 8501, port_to = 8501, protocols = ["tcp"], sources = concat(local.cluster_members, ["boundary-worker"]), desc = "Consul HTTPS API/UI" },
    { to = "consul-server", port_from = 8502, port_to = 8502, protocols = ["tcp"], sources = local.cluster_members, desc = "Consul gRPC (Connect xDS)" },
    { to = "consul-server", port_from = 8600, port_to = 8600, protocols = ["tcp", "udp"], sources = local.cluster_members, desc = "Consul DNS" },
    { to = "nomad-server", port_from = 4646, port_to = 4646, protocols = ["tcp"], sources = concat(local.cluster_members, ["boundary-worker"]), desc = "Nomad HTTP API/UI" },
    { to = "nomad-server", port_from = 4647, port_to = 4647, protocols = ["tcp"], sources = ["nomad-server", "nomad-client"], desc = "Nomad RPC" },
    { to = "nomad-server", port_from = 4648, port_to = 4648, protocols = ["tcp", "udp"], sources = ["nomad-server"], desc = "Nomad Serf gossip (servers only)" },
    { to = "nomad-server", port_from = 8301, port_to = 8301, protocols = ["tcp", "udp"], sources = local.cluster_members, desc = "Consul agent Serf LAN gossip" },
    { to = "nomad-client", port_from = 8301, port_to = 8301, protocols = ["tcp", "udp"], sources = local.cluster_members, desc = "Consul agent Serf LAN gossip" },
    { to = "nomad-client", port_from = 20000, port_to = 32000, protocols = ["tcp"], sources = local.cluster_members, desc = "Nomad dynamic ports (includes Connect sidecars 21000-21255)" },
  ]

  # Flatten to one entry per (destination, port, protocol, source); keys are
  # built from literals only, so the for_each key set is static.
  sg_ingress_rules = {
    for rule in flatten([
      for spec in local.sg_rule_spec : [
        for pair in setproduct(spec.protocols, spec.sources) : {
          key       = "${spec.to}-${spec.port_from}-${pair[0]}-from-${pair[1]}"
          to        = spec.to
          port_from = spec.port_from
          port_to   = spec.port_to
          protocol  = pair[0]
          source    = pair[1]
          desc      = spec.desc
        }
      ]
    ]) : rule.key => rule
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster" {
  for_each = local.sg_ingress_rules

  security_group_id            = local.sg_ids[each.value.to]
  referenced_security_group_id = local.sg_ids[each.value.source]
  from_port                    = each.value.port_from
  to_port                      = each.value.port_to
  ip_protocol                  = each.value.protocol
  description                  = "${each.value.desc} (from ${each.value.source})"

  tags = {
    Name = each.key
  }
}

# The one CIDR-based rule in the cluster, and it must stay: Vault (in HCP)
# validates Nomad workload-identity JWTs by fetching Nomad's JWKS endpoint
# (:4646/.well-known/jwks.json) over the HVN peering. Layer 5 breaks
# silently without it.
resource "aws_vpc_security_group_ingress_rule" "nomad_server_jwks_from_hvn" {
  security_group_id = aws_security_group.nomad_server.id
  cidr_ipv4         = var.hvn_cidr
  from_port         = 4646
  to_port           = 4646
  ip_protocol       = "tcp"
  description       = "Vault (HCP) fetches Nomad JWKS for workload identity"

  tags = {
    Name = "nomad-server-4646-tcp-from-hvn"
  }
}

# Terraform strips AWS's implicit allow-all egress on managed SGs, so
# restore it explicitly. Outbound stays open by design: NAT for packages and
# HCP control-plane reachability, Vault over the peering, and the Boundary
# worker dialing out on 9202. (Exception registered in .checkov.yaml.)
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  for_each = local.sg_ids

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound (NAT, HVN peering, HCP control plane)"

  tags = {
    Name = "${each.key}-all-outbound"
  }
}
