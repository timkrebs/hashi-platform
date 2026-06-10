# Boundary's credential-store token: periodic (Boundary renews it forever)
# and orphan (it must outlive the 6-hour admin token that created it),
# carrying exactly the two policies Layer 3 defined. This token lives in this
# workspace's state — encrypted in HCP Terraform and shared with no client.

resource "vault_token" "boundary_credential_store" {
  display_name      = "boundary-credential-store"
  policies          = data.tfe_outputs.vault_config.nonsensitive_values.boundary_policy_names
  no_parent         = true
  no_default_policy = true
  renewable         = true
  period            = "24h"
}

# worker_filter is the load-bearing detail: Vault has no public endpoint, so
# Boundary routes all Vault API calls through the egress worker, which
# reaches Vault over the VPC -> HVN peering.
resource "boundary_credential_store_vault" "hcp_vault" {
  name        = "hcp-vault"
  description = "HCP Vault Dedicated over the HVN peering (via egress worker)"
  scope_id    = boundary_scope.platform.id

  address   = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_private_endpoint_url
  namespace = data.tfe_outputs.vault_cluster.nonsensitive_values.vault_namespace
  token     = vault_token.boundary_credential_store.client_token

  worker_filter = "\"vault\" in \"/tags/type\""
}

# Per-session SSH certificate: Boundary generates an ed25519 keypair, Vault
# signs the public key with the boundary-client role, and the certificate is
# INJECTED into the session — it never reaches the operator's machine.
resource "boundary_credential_library_vault_ssh_certificate" "ssh_cert" {
  name                = "vault-ssh-cert"
  description         = "Short-lived Vault-signed SSH certificates for ec2-user"
  credential_store_id = boundary_credential_store_vault.hcp_vault.id

  path     = "${data.tfe_outputs.vault_config.nonsensitive_values.ssh_mount_path}/sign/${data.tfe_outputs.vault_config.nonsensitive_values.ssh_role_name}"
  username = "ec2-user"
  key_type = "ed25519"

  extensions = {
    permit-pty = ""
  }
}
