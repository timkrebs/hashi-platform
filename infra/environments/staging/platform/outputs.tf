output "argocd_port_forward" {
  description = "Command that exposes the Argo CD UI on http://localhost:8080."
  value       = module.argocd.port_forward_command
}

output "argocd_initial_admin_password" {
  description = "Command that prints the initial Argo CD admin password."
  value       = module.argocd.initial_admin_password_command
}

output "gitops_source" {
  description = "Repository, revision and path the root Application tracks."
  value       = module.argocd_root_app.source
}

output "vault_kms_key_alias" {
  description = "Alias of Vault's auto-unseal key."
  value       = module.vault_prerequisites.kms_key_alias
}

output "vault_irsa_role_arn" {
  description = "IAM role the Vault server assumes to use the unseal key."
  value       = module.vault_prerequisites.vault_irsa_role_arn
}

output "vault_init_secret_name" {
  description = "Secrets Manager secret that receives Vault's recovery keys, root token and CA after init."
  value       = module.vault_prerequisites.init_secret_name
}

output "cluster_secret_annotations" {
  description = "Values handed to Argo CD ApplicationSets through the in-cluster secret."
  value       = local.cluster_secret_annotations
}
