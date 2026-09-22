# Anforderung 2: request.data.data kann ganz fehlen. Ohne den else-Guard
# bricht die Policy hier mit einem Undefined-Fehler ab statt zu entscheiden.
global "request" {
  value = {
    operation = "create"
    path      = "kv/data/backend/auth-service/signing-secret"
    data      = {}
  }
}

test {
  rules = {
    main         = false
    data_present = false

    # Der eigentliche Beweis fuer den else-Guard. Mit ihm ist secret_data eine
    # leere Map und diese Regel leer-wahr; ohne ihn ist sie undefined und die
    # Assertion schlaegt fehl. Nur "main = false" zu pruefen wuerde auch dann
    # gruen bleiben, wenn die Policy gar nicht mehr entscheidet.
    keys_match_convention = true
  }
}
