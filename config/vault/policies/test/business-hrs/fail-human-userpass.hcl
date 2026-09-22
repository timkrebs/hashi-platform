# Mensch ueber userpass: userpass steht bewusst NICHT in exempt_auth_types.
# 2026-07-12 ist ein Sonntag (weekday 0), 03:00 UTC.
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

global "identity" { value = { entity = { aliases = [ { mount_type = "userpass" } ] } } }
global "token"    { value = {} }

test {
  rules = {
    main = false
    is_service_identity = false
  }
}
