# Montag NACH der Umstellung: CEST (+2), 07 UTC = 09 lokal -> erlaubt.
# 2026-03-30 ist ein Montag (weekday 1), 07:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 3
      day     = 30
      hour    = 7
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
