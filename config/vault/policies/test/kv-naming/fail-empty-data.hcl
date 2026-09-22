# Schreiben ohne Inhalt. Wichtig, weil `all` ueber eine leere Collection in
# Sentinel `true` ergibt -- keys_match_convention waere hier also erfuellt und
# der Fall schluepfte ohne eine eigene Regel durch.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data      = { data = {} }
  }
}

test {
  rules = {
    main                  = false
    data_present          = false
    keys_match_convention = true
  }
}
