# Spiegelbild: der Key ENDET konform. Ohne ^ im key_pattern matcht der hintere
# Teil und ein beliebiges Praefix waere erlaubt.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data      = { data = { LEGACY_APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                  = false
    keys_match_convention = false
  }
}
