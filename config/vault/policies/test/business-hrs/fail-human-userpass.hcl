# Mensch ueber userpass: auth/userpass/ steht bewusst NICHT in
# exempt_auth_paths.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 12
      hour    = 3
      weekday = 0
    }
  }
}

global "token"    { value = { path = "auth/userpass/login/timkrebs", policies = ["dev"] } }

test {
  rules = {
    main = false
    is_service_identity = false
  }
}
