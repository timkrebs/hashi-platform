# Obergrenze exakt: 15 UTC = 17 lokal, bereits ausserhalb (halboffen).
# 2026-07-14 ist ein Dienstag (weekday 2), 15:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 14
      hour    = 15
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
