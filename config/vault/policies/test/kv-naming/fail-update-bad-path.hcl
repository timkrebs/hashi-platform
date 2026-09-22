# Ein nicht konformes UPDATE. Der bestehende pass-update-Fall beweist nur,
# dass ein konformes Update durchgeht -- das taete es auch, wenn update gar
# nicht mehr geprueft wuerde. Erst ein Update, das scheitern MUSS, haelt
# update in write_operations fest.
global "request" {
  value = {
    operation = "update"
    path      = "kv/data/backend/auth-service/signing"
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
