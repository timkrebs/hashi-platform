#------------------------------------------------------------------------
# Hashi Platform: HCP Vault - Static secrets
#------------------------------------------------------------------------

resource "vault_policy" "admin_policy" {
  name   = "admin-policy"
  policy = file("policies/admin-policy.hcl")
}

