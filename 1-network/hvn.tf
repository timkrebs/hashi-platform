# HVN + VPC peering: the private path between HCP-managed products (Vault,
# Boundary control plane side) and the workload VPC. Vault is reached on
# :8200 over this peering; Vault fetches Nomad's JWKS back over it.

# The HVN CIDR is PERMANENT (172.25.16.0/20). Changing it forces destroying
# every HCP cluster inside the HVN — never modify after creation.
resource "hcp_hvn" "main" {
  hvn_id         = "${local.name_prefix}-hvn"
  cloud_provider = "aws"
  region         = var.aws_region
  cidr_block     = var.hvn_cidr
}

resource "hcp_aws_network_peering" "main" {
  hvn_id          = hcp_hvn.main.hvn_id
  peering_id      = "${local.name_prefix}-vpc"
  peer_vpc_id     = aws_vpc.main.id
  peer_account_id = aws_vpc.main.owner_id
  peer_vpc_region = var.aws_region
}

resource "aws_vpc_peering_connection_accepter" "hvn" {
  vpc_peering_connection_id = hcp_aws_network_peering.main.provider_peering_id
  auto_accept               = true

  tags = {
    Name = "${local.name_prefix}-hvn"
  }
}

resource "hcp_hvn_route" "to_vpc" {
  hvn_link         = hcp_hvn.main.self_link
  hvn_route_id     = "${local.name_prefix}-to-vpc"
  destination_cidr = aws_vpc.main.cidr_block
  target_link      = hcp_aws_network_peering.main.self_link

  depends_on = [aws_vpc_peering_connection_accepter.hvn]
}

resource "aws_route" "private_to_hvn" {
  for_each = toset(local.azs)

  route_table_id            = aws_route_table.private[each.key].id
  destination_cidr_block    = var.hvn_cidr
  vpc_peering_connection_id = hcp_aws_network_peering.main.provider_peering_id
}
