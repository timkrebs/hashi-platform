# Ausnahme ueber die Policy vault-automation -- der Weg fuer Break-glass
# und fuer alles, was sich nicht am Auth-Mount erkennen laesst.
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

global "token"    { value = { path = "auth/token/create", policies = ["default", "vault-automation"] } }

test {
  rules = {
    main = true
    is_service_identity = true
  }
}
