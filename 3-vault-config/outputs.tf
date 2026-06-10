output "boundary_policy_names" {
  description = "Vault policies for Boundary's credential-store token (Layer 7 mints the token with exactly these)"
  value = [
    vault_policy.boundary_controller.name,
    vault_policy.ssh_signer.name,
  ]
}

output "ssh_mount_path" {
  description = "Mount path of the SSH client signer engine"
  value       = vault_mount.ssh.path
}

output "ssh_role_name" {
  description = "SSH signing role used by Boundary's credential library"
  value       = vault_ssh_secret_backend_role.boundary_client.name
}
