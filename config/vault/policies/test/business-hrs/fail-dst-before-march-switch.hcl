# Freitag VOR der Umstellung: noch CET (+1), 07:30 UTC = 08 lokal -> abgelehnt.
# Mit falscher Zeitzone (immer +2) waere es 09 lokal und der Test wuerde durchgehen.
# 2026-03-27 ist ein Freitag (weekday 5), 07:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 3
      day     = 27
      hour    = 7
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
