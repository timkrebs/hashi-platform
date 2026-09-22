# Doppelter Bindestrich. Faellt nur durch, weil das Segment als
# [a-z0-9]+(-[a-z0-9]+)* geschrieben ist; ein [a-z0-9-]+ liesse es zu.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth--service/signing-secret"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
