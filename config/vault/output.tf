output "admin_login_command" {
  description = "Logs in as the administrator. Use this instead of the root token, and revoke the root token once it works."
  value       = "vault login -address=${var.vault_address} -method=userpass username=${var.admin_username}"
}

output "dev1_login_command" {
  description = "Logs dev1 into the backend namespace. The namespace flag is required: dev1 does not exist anywhere else."
  value       = "vault login -address=${var.vault_address} -namespace=${vault_namespace.backend.path} -method=userpass username=dev1"
}

output "dev2_login_command" {
  description = "Logs dev2 into the frontend namespace."
  value       = "vault login -address=${var.vault_address} -namespace=${vault_namespace.frontend.path} -method=userpass username=dev2"
}

output "namespaces" {
  description = "Namespaces created by this configuration."
  value       = [vault_namespace.backend.path, vault_namespace.frontend.path]
}

output "root_ca_certificate" {
  description = "Root CA certificate in PEM form. Distribute it to anything that has to trust the development certificates."
  value       = vault_pki_secret_backend_root_cert.root.certificate
}

output "backend_issue_command" {
  description = "Issues a development certificate as dev1."
  value       = "vault write -namespace=${vault_namespace.backend.path} ${vault_mount.backend_pki.path}/issue/${vault_pki_secret_backend_role.backend_dev.name} common_name=app.${var.pki_allowed_domains[0]} ttl=24h"
}

output "backend_api_key_command" {
  description = "Reads the backend demo API key."
  value       = "vault kv get -namespace=${vault_namespace.backend.path} ${vault_mount.backend_kv.path}/${vault_kv_secret_v2.backend_api_key.name}"
}

output "frontend_api_key_command" {
  description = "Reads the frontend demo API key."
  value       = "vault kv get -namespace=${vault_namespace.frontend.path} ${vault_mount.frontend_kv.path}/${vault_kv_secret_v2.frontend_api_key.name}"
}

# The demo keys themselves are deliberately not outputs: they live in Vault,
# which is the point of the exercise, and an output would copy them into the
# HCP run view.

output "checkmk_approle_role_id" {
  description = "Role ID of the monitoring AppRole. Not a secret on its own; it needs a secret ID to log in."
  value       = vault_approle_auth_backend_role.checkmk.role_id
}

output "checkmk_secret_id_command" {
  description = "Creates a secret ID for the monitoring AppRole. Run it out of band: generating one in Terraform would put a long-lived credential into state."
  value       = "vault write -f auth/${vault_auth_backend.approle.path}/role/${vault_approle_auth_backend_role.checkmk.role_name}/secret-id"
}
