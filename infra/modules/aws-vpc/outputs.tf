output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "availability_zones" {
  description = "Availability zones the subnets were created in, in the same order as the subnet lists."
  value       = local.azs

  precondition {
    condition     = local.available_az_count >= var.az_count
    error_message = "az_count is ${var.az_count} but only ${local.available_az_count} availability zones are available in this region."
  }
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, one per availability zone. Use these for EKS nodes and internal load balancers."
  value       = module.vpc.private_subnets
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets, in the same order as private_subnet_ids."
  value       = local.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, one per availability zone. Use these for internet-facing load balancers."
  value       = module.vpc.public_subnets
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets, in the same order as public_subnet_ids."
  value       = local.public_subnets
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateways. Allow-list these where private workloads need to reach external services."
  value       = module.vpc.nat_public_ips
}
