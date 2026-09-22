# Key nicht in UPPER_SNAKE_CASE. Der Pfad ist korrekt, damit der Fall
# eindeutig der Key-Regel zuzuordnen ist.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data      = { data = { app_token = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = true
    keys_match_convention   = false
  }
}
