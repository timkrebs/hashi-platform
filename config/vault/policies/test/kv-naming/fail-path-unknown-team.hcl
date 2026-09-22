# Erstes Segment ist kein bekanntes Team (backend|frontend|platform).
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/payments/checkout/db-secret"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
