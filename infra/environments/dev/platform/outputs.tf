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

output "argocd_port_forward" {
  description = "Command that exposes the Argo CD UI on http://localhost:8080."
  value       = one(module.argocd[*].port_forward_command)
}

output "argocd_initial_admin_password" {
  description = "Command that prints the initial Argo CD admin password."
  value       = one(module.argocd[*].initial_admin_password_command)
}

output "argocd_bootstrap_command" {
  description = "One-off command that hands Argo CD the root Application. Everything under gitops/apps follows from it."
  value       = "kubectl apply -f gitops/bootstrap/root-app.yaml"
}

output "vault_kms_key_alias" {
  description = "Alias of Vault's auto-unseal key. The Helm values reference this alias rather than the key ID, because the alias survives a rebuild of the environment."
  value       = one(module.vault_prerequisites[*].kms_key_alias)
}

output "vault_init_secret_name" {
  description = "Secrets Manager secret that receives Vault's recovery keys, root token and CA after init."
  value       = one(module.vault_prerequisites[*].init_secret_name)
}

output "vault_license_secret_command" {
  description = "Creates the Enterprise license secret. Run it out of band: the licence must never be committed to this public repository."
  value       = "kubectl create secret generic vault-ent-license --namespace ${var.vault_namespace} --from-file=license=vault.hclic"
}
