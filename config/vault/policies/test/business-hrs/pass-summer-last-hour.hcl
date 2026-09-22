# Obergrenze innen: 14 UTC = 16 lokal.
# 2026-07-14 ist ein Dienstag (weekday 2), 14:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 14
      hour    = 14
      weekday = 2
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
