# Untergrenze exakt: 07 UTC = 09 lokal, erster erlaubter Wert.
# 2026-07-14 ist ein Dienstag (weekday 2), 07:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 14
      hour    = 7
      weekday = 2
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
