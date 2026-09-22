# Wochentagsgrenze: sunday.
# 2026-07-12 ist ein Sonntag (weekday 0), 10:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 12
      hour    = 10
      weekday = 0
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
