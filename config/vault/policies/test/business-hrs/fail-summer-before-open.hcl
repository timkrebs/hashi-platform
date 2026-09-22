# Untergrenze knapp verfehlt: 06 UTC = 08 lokal.
# 2026-07-14 ist ein Dienstag (weekday 2), 06:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 14
      hour    = 6
      weekday = 2
    }
  }
}

global "token"    { value = { path = "auth/userpass/login/timkrebs", policies = ["dev", "default"] } }

test {
  rules = {
    main = false
    within_workhours = false
    within_workdays = true
  }
}
