# Local Zones and Wavelength Zones are opt-in and are not supported by EKS
# managed node groups, so only regular availability zones are considered.
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  available_az_count = length(data.aws_availability_zones.available.names)
  azs                = slice(data.aws_availability_zones.available.names, 0, min(var.az_count, local.available_az_count))

  vpc_prefix_length = tonumber(split("/", var.cidr_block)[1])
  subnet_newbits    = var.subnet_prefix_length - local.vpc_prefix_length

  # Private subnets take the first az_count blocks, public subnets the next
  # az_count blocks. With the defaults (10.0.0.0/16, three zones, /24 subnets)
  # this yields 10.0.0.0/24-10.0.2.0/24 private and 10.0.3.0/24-10.0.5.0/24 public.
  private_subnets = tolist([for i in range(var.az_count) : cidrsubnet(var.cidr_block, local.subnet_newbits, i)])
  public_subnets  = tolist([for i in range(var.az_count) : cidrsubnet(var.cidr_block, local.subnet_newbits, var.az_count + i)])
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = var.name
  cidr = var.cidr_block
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # The AWS Load Balancer Controller discovers subnets for internet-facing and
  # internal load balancers through these role tags.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}
