# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region

  # Applied to every taggable AWS resource in this configuration
  default_tags {
    tags = local.common_tags
  }
}

# Filter out local zones, which are not currently supported
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Naming convention: {prefix}-{env}-{region}-{component}[-{qualifier}][-{az}]
  # e.g. hp-dev-euc1-eks-ng-default
  region_short = {
    "eu-central-1" = "euc1"
    "eu-north-1"   = "eun1"
    "us-east-1"    = "use1"
  }

  name_prefix = "${var.prefix}-${var.env}-${local.region_short[var.region]}"

  vpc_name     = "${local.name_prefix}-vpc"
  cluster_name = "${local.name_prefix}-eks"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  common_tags = {
    prefix = var.prefix
    env    = var.env
    region = local.region_short[var.region]
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = local.vpc_name

  cidr = "10.0.0.0/16"
  azs  = local.azs

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  # Subnet names carry the {az} token, e.g. hp-dev-euc1-snet-private-1a
  private_subnet_names = [for az in local.azs : "${local.name_prefix}-snet-private-${substr(az, length(az) - 2, 2)}"]
  public_subnet_names  = [for az in local.azs : "${local.name_prefix}-snet-public-${substr(az, length(az) - 2, 2)}"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = "1.34"

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"

  }

  eks_managed_node_groups = {
    one = {
      name = "${local.name_prefix}-eks-ng-default"

      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

    two = {
      name = "${local.name_prefix}-eks-ng-spare"

      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${local.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}
