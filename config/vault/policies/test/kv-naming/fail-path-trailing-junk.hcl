# Das Segment endet nicht auf -secret, es ENTHAELT es nur. Ohne das $-Anker im
# Regex matcht "signing-secret" als Praefix von "signing-secret-v2" und der
# Pfad geht durch. Dieser Fall existiert genau deshalb.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret-v2"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
