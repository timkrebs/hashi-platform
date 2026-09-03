provider "aws" {
  region = var.region
}

module "network" {
  source = "../../../modules/aws-vpc"

  name       = "${local.cluster_name}-vpc"
  cidr_block = var.vpc_cidr_block
  az_count   = var.az_count

  # Production keeps one NAT gateway per availability zone so the loss of a
  # zone does not take private egress down with it.
  single_nat_gateway = false

  tags = local.common_tags
}

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  node_groups = var.node_groups

  tags = local.common_tags
}
