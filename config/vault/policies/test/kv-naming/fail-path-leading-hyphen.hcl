# Fuehrender Bindestrich in einem Segment. Ein naiver Regex wie [a-z0-9-]+
# laesst das durch -- deshalb ein eigener Fall.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/-auth-service/signing-secret"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
