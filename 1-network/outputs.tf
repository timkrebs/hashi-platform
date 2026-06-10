# Consumed by later layers via the `tfe_outputs` data source, e.g.:
#   data "tfe_outputs" "network" {
#     organization = "<org>"
#     workspace    = "1-network"
#   }

output "auto_join" {
  description = "EC2 tag key/values for Consul and Nomad cloud auto-join — Layers 4/5 must tag instances with these"
  value       = local.auto_join
}

output "aws_peering_connection_id" {
  description = "AWS-side VPC peering connection ID (pcx-...)"
  value       = aws_vpc_peering_connection_accepter.hvn.id
}

output "hvn_cidr" {
  description = "HVN CIDR (permanent)"
  value       = hcp_hvn.main.cidr_block
}

output "hvn_id" {
  description = "HVN ID — Layer 2 provisions Vault Dedicated inside it"
  value       = hcp_hvn.main.hvn_id
}

output "hvn_self_link" {
  description = "HVN self link for HCP resources that reference the network"
  value       = hcp_hvn.main.self_link
}

output "instance_profile_arns" {
  description = "Instance profile ARNs by node role"
  value       = { for role, profile in aws_iam_instance_profile.node : role => profile.arn }
}

output "instance_profile_names" {
  description = "Instance profile names by node role"
  value       = { for role, profile in aws_iam_instance_profile.node : role => profile.name }
}

output "instance_role_names" {
  description = "IAM role names by node role, for later layers to attach scoped policies"
  value       = { for role, iam_role in aws_iam_role.node : role => iam_role.name }
}

output "private_route_table_ids" {
  description = "Private route table IDs by AZ suffix"
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "private_subnet_ids" {
  description = "Private subnet IDs by AZ suffix — all compute lands here"
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "public_subnet_ids" {
  description = "Public subnet IDs by AZ suffix (NAT only)"
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "security_group_ids" {
  description = "Security group IDs by node role"
  value       = local.sg_ids
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = aws_vpc.main.cidr_block
}

output "vpc_id" {
  description = "Workload VPC ID"
  value       = aws_vpc.main.id
}
