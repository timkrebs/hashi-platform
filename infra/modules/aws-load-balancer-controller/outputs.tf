output "iam_role_arn" {
  description = "ARN of the IAM role the controller assumes through IRSA."
  value       = module.irsa.iam_role_arn
}

output "release_name" {
  description = "Name of the Helm release."
  value       = helm_release.this.name
}

output "namespace" {
  description = "Namespace the controller runs in."
  value       = helm_release.this.namespace
}

output "chart_version" {
  description = "Installed chart version."
  value       = helm_release.this.version
}
