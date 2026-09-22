# Der Pfad beginnt mit kv/data/ (kommt also durch is_kv_write) und enthaelt
# weiter hinten eine konforme Sequenz. Ohne ^ im path_pattern matcht genau die
# und der Schreibzugriff waere erlaubt.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/wildwuchs/kv/data/backend/auth-service/signing-secret"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    is_kv_write             = true
    path_matches_convention = false
  }
}
