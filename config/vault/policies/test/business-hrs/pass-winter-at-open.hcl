# Winter, Untergrenze exakt: 08 UTC = 09 lokal. Im Sommer waere 08 UTC bereits 10 lokal -- dieser Fall haelt die Zeitzone fest.
# 2026-01-14 ist ein Mittwoch (weekday 3), 08:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 1
      day     = 14
      hour    = 8
      weekday = 3
    }
  }
}

global "identity" { value = {} }
global "token"    { value = {} }

test {
  rules = {
    main = true
    within_workhours = true
  }
}
