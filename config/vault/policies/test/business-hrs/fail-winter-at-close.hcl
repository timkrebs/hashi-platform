# Winter, Obergrenze exakt: 16 UTC = 17 lokal.
# 2026-01-14 ist ein Mittwoch (weekday 3), 16:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 1
      day     = 14
      hour    = 16
      weekday = 3
    }
  }
}

global "identity" { value = {} }
global "token"    { value = {} }

test {
  rules = {
    main = false
    within_workhours = false
    within_workdays = true
  }
}
