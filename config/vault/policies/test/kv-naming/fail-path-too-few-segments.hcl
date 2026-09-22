# Genau der Altbestand: kv/data/api-key, ein Segment. Belegt, dass die Policy
# ihn unter hard-mandatory ablehnen wuerde.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/api-key"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
