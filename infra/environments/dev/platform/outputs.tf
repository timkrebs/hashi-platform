output "load_balancer_controller_role_arn" {
  description = "IAM role the AWS Load Balancer Controller assumes through IRSA."
  value       = module.aws_load_balancer_controller.iam_role_arn
}

output "cert_manager_namespace" {
  description = "Namespace cert-manager runs in, or null when it is disabled."
  value       = one(module.cert_manager[*].namespace)
}
