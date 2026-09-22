# Weder Entity noch Policies. Belegt die else-Guards: ohne sie wuerde die
# Regel undefined statt false und die Policy entschiede gar nicht.
# 2026-07-12 ist ein Sonntag (weekday 0), 03:00 UTC.
mock "time" {
  data = {
    now = {
      year    = 2026
      month   = 7
      day     = 12
      hour    = 3
      weekday = 0
    }
  }
}

global "identity" { value = {} }
global "token"    { value = {} }

test {
  rules = {
    main = false
    is_service_identity = false
  }
}
