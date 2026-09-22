# Wochentagsgrenze: friday.
# 2026-07-17 ist ein Freitag (weekday 5), 10:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 17
      hour    = 10
      weekday = 5
    }
  }
}

global "token"    { value = { path = "auth/userpass/login/timkrebs", policies = ["dev", "default"] } }

test {
  rules = {
    main = true
    within_workdays = true
  }
}
