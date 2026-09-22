# Token OHNE jedes Feld -- weder path noch policies. Belegt die else-Guards
# auf den FELDERN. Dass der Bezeichner `token` selbst fehlen kann, laesst
# sich hier nicht pruefen: Sentinel bricht dann mit "unknown identifier"
# ab, und genau daran ist die Vorversion dieser Policy in Vault gescheitert,
# weil sie identity las. Deshalb darf die Policy nur an authentifizierte
# Pfade gehaengt werden.
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

global "token"    { value = {} }

test {
  rules = {
    main = false
    is_service_identity = false
  }
}
