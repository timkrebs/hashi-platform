# Service-Identitaet: der Token stammt aus dem kubernetes-Auth-Mount.
# token.path ist der Pfad, der den Token erzeugt hat -- so laesst sich das
# Auth-Verfahren erkennen, ohne identity anzufassen.
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

global "token"    { value = { path = "auth/kubernetes/login", policies = ["default"] } }

test {
  rules = {
    main = true
    is_service_identity = true
  }
}
