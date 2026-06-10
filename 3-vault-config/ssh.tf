# SSH certificate authority: Vault signs a short-lived user certificate per
# Boundary session; targets trust the CA's public key (fetched unauthenticated
# from <mount>/public_key at instance boot). No SSH keypairs exist anywhere.

resource "vault_mount" "ssh" {
  path        = var.ssh_mount_path
  type        = "ssh"
  description = "Client SSH certificate signing for Boundary-brokered sessions"
}

resource "vault_ssh_secret_backend_ca" "ssh" {
  backend              = vault_mount.ssh.path
  generate_signing_key = true
}

resource "vault_ssh_secret_backend_role" "boundary_client" {
  name    = "boundary-client"
  backend = vault_mount.ssh.path

  key_type                = "ca"
  allow_user_certificates = true
  default_user            = "ec2-user"
  allowed_users           = "ec2-user"

  # rsa-sha2-512 because modern sshd rejects legacy ssh-rsa (SHA-1) CA
  # signatures.
  algorithm_signer = "rsa-sha2-512"

  default_extensions = {
    permit-pty = ""
  }
  allowed_extensions = "permit-pty"

  # Certificates only need to outlive the session handshake.
  ttl     = "300"
  max_ttl = "600"
}
