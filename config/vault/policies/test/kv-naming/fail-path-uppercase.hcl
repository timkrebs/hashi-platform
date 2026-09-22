# Grossbuchstaben im Pfad.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/Auth-Service/signing-secret"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
    keys_match_convention   = true
  }
}
