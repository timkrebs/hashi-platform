# Der Key BEGINNT konform und haengt dann Unerlaubtes an. Ohne $ im
# key_pattern matcht "APP_TOKEN" als Praefix und der Bindestrich rutscht durch.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data      = { data = { APP_TOKEN-LEGACY = "…" } }
  }
}

test {
  rules = {
    main                  = false
    keys_match_convention = false
  }
}
