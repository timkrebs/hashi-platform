# Wochentagsgrenze: monday.
# 2026-07-13 ist ein Montag (weekday 1), 10:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 13
      hour    = 10
      weekday = 1
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
