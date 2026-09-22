# Letztes Segment endet nicht auf -secret.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
