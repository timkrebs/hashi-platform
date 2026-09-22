# Winter, Untergrenze verfehlt: 07 UTC = 08 lokal.
# 2026-01-14 ist ein Mittwoch (weekday 3), 07:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 1
      day     = 14
      hour    = 7
      weekday = 3
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
