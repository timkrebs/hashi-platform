output "load_balancer_controller_role_arn" {
  description = "IAM role the AWS Load Balancer Controller assumes through IRSA."
  value       = module.aws_load_balancer_controller.iam_role_arn
}

output "cert_manager_namespace" {
  description = "Namespace cert-manager runs in, or null when it is disabled."
  value       = one(module.cert_manager[*].namespace)
}

output "checkmk_url" {
  description = "URL of the Checkmk web interface, or null when the server is disabled. The certificate is self-signed."
  value       = one(module.checkmk[*].url)
}

output "checkmk_public_ip" {
  description = "Elastic IP of the Checkmk server."
  value       = one(module.checkmk[*].public_ip)
}

output "checkmk_instance_id" {
  description = "Instance ID of the Checkmk server."
  value       = one(module.checkmk[*].instance_id)
}

output "checkmk_admin_password_command" {
  description = "Command that prints the initial cmkadmin password from SSM Parameter Store."
  value       = one(module.checkmk[*].admin_password_command)
}

output "checkmk_session_manager_command" {
  description = "Command that opens a shell on the Checkmk server through SSM Session Manager."
  value       = one(module.checkmk[*].session_manager_command)
}
