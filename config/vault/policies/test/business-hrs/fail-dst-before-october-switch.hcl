# Freitag VOR der Rueckstellung: noch CEST (+2), 15 UTC = 17 lokal -> abgelehnt.
# 2026-10-23 ist ein Freitag (weekday 5), 15:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 10
      day     = 23
      hour    = 15
      weekday = 5
    }
  }
}

global "identity" { value = {} }
global "token"    { value = {} }

test {
  rules = {
    main = false
    within_workhours = false
  }
}
