# Winter, Obergrenze innen: 15 UTC = 16 lokal.
# 2026-01-14 ist ein Mittwoch (weekday 3), 15:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 1
      day     = 14
      hour    = 15
      weekday = 3
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
