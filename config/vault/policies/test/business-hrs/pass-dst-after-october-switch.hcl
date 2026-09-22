# Montag NACH der Rueckstellung: CET (+1), 15 UTC = 16 lokal -> erlaubt.
# 2026-10-26 ist ein Montag (weekday 1), 15:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 10
      day     = 26
      hour    = 15
      weekday = 1
    }
  }
}

global "token"    { value = { path = "auth/userpass/login/timkrebs", policies = ["dev", "default"] } }

test {
  rules = {
    main = true
    within_workhours = true
  }
}
