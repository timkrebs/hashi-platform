# Wochentagsgrenze: saturday.
# 2026-07-18 ist ein Samstag (weekday 6), 10:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 18
      hour    = 10
      weekday = 6
    }
  }
}

global "token"    { value = { path = "auth/userpass/login/timkrebs", policies = ["dev", "default"] } }

test {
  rules = {
    main = false
    within_workdays = false
  }
}
