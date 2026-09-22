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

global "identity" { value = {} }
global "token"    { value = {} }

test {
  rules = {
    main = true
    within_workdays = true
  }
}
