# Key ohne APP_-Praefix.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data      = { data = { DB_PASSWORD = "…" } }
  }
}

test {
  rules = {
    main                    = false
    keys_match_convention   = false
  }
}
