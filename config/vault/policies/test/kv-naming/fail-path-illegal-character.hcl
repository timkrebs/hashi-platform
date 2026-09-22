# Unterstrich ist im Pfad nicht erlaubt (nur a-z, 0-9, Bindestrich).
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth_service/signing-secret"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
