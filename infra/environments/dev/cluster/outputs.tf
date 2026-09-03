output "region" {
  description = "AWS region of the environment."
  value       = var.region
}

output "vpc_id" {
  description = "ID of the environment VPC."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, for workloads deployed next to the cluster."
  value       = module.network.private_subnet_ids
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group attached to the control plane network interfaces."
  value       = module.eks.cluster_security_group_id
}

output "configure_kubectl" {
  description = "Command that writes a kubeconfig entry for the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# Consumed by the platform layer through HCP Terraform remote state.
output "environment" {
  description = "Environment name."
  value       = local.environment
}

output "project" {
  description = "Project name."
  value       = local.project
}

output "account_id" {
  description = "AWS account the environment lives in."
  value       = data.aws_caller_identity.current.account_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the environment VPC."
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, for internet-facing load balancers."
  value       = module.network.public_subnet_ids
}

output "cluster_version" {
  description = "Kubernetes version of the control plane."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data of the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "node_security_group_id" {
  description = "Security group shared by the managed node groups."
  value       = module.eks.node_security_group_id
}

output "oidc_provider" {
  description = "OIDC issuer URL of the cluster without the https:// prefix, for IRSA trust policies."
  value       = module.eks.oidc_provider
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  value       = module.eks.oidc_provider_arn
}
