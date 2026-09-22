# Untergrenze exakt: 07 UTC = 09 lokal, erster erlaubter Wert.
# 2026-07-14 ist ein Dienstag (weekday 2), 07:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 14
      hour    = 7
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
