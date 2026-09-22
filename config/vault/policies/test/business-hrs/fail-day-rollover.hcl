# Freitag 23 UTC im Sommer ist in Berlin bereits Samstag 01 Uhr.
# Ohne die Tagesuebergangs-Korrektur bliebe local_weekday 5 und within_workdays waere true.
# 2026-07-17 ist ein Freitag (weekday 5), 23:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 17
      hour    = 23
      weekday = 5
    }
  }
}

global "identity" { value = {} }
global "token"    { value = {} }

test {
  rules = {
    main = false
    within_workdays = false
  }
}
