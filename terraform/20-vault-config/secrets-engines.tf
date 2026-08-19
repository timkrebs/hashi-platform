#------------------------------------------------------------------------
# Hashi Platform: HCP Vault - Secrets engines
#------------------------------------------------------------------------

resource "vault_mount" "kv_v2" {
  path = "kv-v2"
  type = "kv-v2"
}

resource "vault_mount" "pki" {
  path = "pki"
  type = "pki"
}