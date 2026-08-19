#------------------------------------------------------------------------
# Hashi Platform: HCP Vault - Static secrets
#------------------------------------------------------------------------

# Provision some static secrets in the KV secrets engine at the path 'kv-v2'

resource "vault_kv_secret_v2" "static_secrets" {
  mount = "kv-v2"
  name  = "static-secrets"

  data_json = <<EOT
{
  "admin": "user",
  "password": "V9QZ8l6xzhZGkq8jsUjpwvRMIWLRIMGWgnNqSWwT0gU2"
}
EOT

  depends_on = [
    vault_mount.kv_v2
  ]
}

resource "vault_kv_secret_v2" "static_secrets_2" {
  mount = "kv-v2"
  name  = "static-secrets-2"

  data_json = <<EOT
{
  "admin": "user",
  "password": "V9QZ8l6xzhZGkq8jsUjpwvRMIWLRIMGWgnNqSWwT0gU2"
}
EOT
    depends_on = [
        vault_mount.kv_v2
    ]
}

resource "vault_pki_secret_backend_role" "example" {
  backend = vault_mount.pki.path
  name    = "example-dot-com"

  allowed_domains    = ["example.com"]
  allow_subdomains   = true
  max_ttl            = "72h"
  allow_any_name     = true
  enforce_hostnames  = false
  allow_bare_domains = true

  depends_on = [
    vault_mount.pki
  ]
}
