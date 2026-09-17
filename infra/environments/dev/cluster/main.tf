provider "aws" {
  region = var.region
}

module "network" {
  source = "../../../modules/aws-vpc"

  name       = "${local.cluster_name}-vpc"
  cidr_block = var.vpc_cidr_block
  az_count   = var.az_count

  # One shared NAT gateway keeps the dev bill down at the cost of zone redundancy.
  single_nat_gateway = true

  tags = local.common_tags
}

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  node_groups = var.node_groups

  # Compliance: run the nodes on the company's hardened EKS image. The image is
  # selected by cluster_version, and one is only published for some versions, so
  # this cannot be turned on until the control plane is on a version that has one.
  use_hardened_node_ami = var.use_hardened_node_ami

  # Dev is ephemeral and rebuilt often; schedule the old secrets key for
  # deletion after the minimum window instead of the 30-day default.
  kms_key_deletion_window_in_days = 7

  tags = local.common_tags
}

# EKS only moves one minor version per update, and it checks against the live
# cluster. Getting that wrong fails halfway through an apply, which is a far
# worse place to find out than the plan.
#
# This is a check block rather than a precondition on purpose: a data source
# that fails inside one degrades to a warning, so a first-ever create (no
# cluster to describe yet) still plans cleanly.
check "cluster_version_moves_one_minor_at_a_time" {
  data "aws_eks_cluster" "live" {
    name = local.cluster_name
  }

  assert {
    condition = (
      tonumber(split(".", var.cluster_version)[1]) -
      tonumber(split(".", data.aws_eks_cluster.live.version)[1])
    ) <= 1
    error_message = format(
      "cluster_version is %s but the live cluster is %s. EKS rejects a jump of more than one minor version; go to 1.%d first.",
      var.cluster_version,
      data.aws_eks_cluster.live.version,
      tonumber(split(".", data.aws_eks_cluster.live.version)[1]) + 1,
    )
  }
}
