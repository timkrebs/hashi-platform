# Vier Segmente statt drei. Ohne $-Anker matcht der Regex die ersten drei und
# ignoriert den Rest.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret/extra"
    data      = { data = { APP_TOKEN = "…" } }
  }
}

test {
  rules = {
    main                    = false
    path_matches_convention = false
  }
}
