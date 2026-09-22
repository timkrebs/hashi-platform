# Service-Identitaet ueber das kubernetes-Auth-Mount: ausgenommen, obwohl Sonntagnacht.
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

global "identity" { value = { entity = { aliases = [ { mount_type = "kubernetes" } ] } } }
global "token"    { value = {} }

test {
  rules = {
    main = true
    is_service_identity = true
  }
}
