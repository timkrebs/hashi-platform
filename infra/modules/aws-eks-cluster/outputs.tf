output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster, as used in kubeconfig."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "ID of the security group attached to the control plane network interfaces."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the security group shared by all managed node groups. Add rules here to let other resources reach the nodes."
  value       = module.eks.node_security_group_id
}

output "oidc_provider" {
  description = "OIDC issuer URL of the cluster without the https:// prefix. Use it to build IRSA trust policies."
  value       = module.eks.oidc_provider
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for the cluster."
  value       = module.eks.oidc_provider_arn
}

output "ebs_csi_irsa_role_arn" {
  description = "ARN of the IAM role assumed by the EBS CSI driver."
  value       = module.ebs_csi_irsa.iam_role_arn
}
