# Der 25. Maerz 2030 ist ein Montag, also day - weekday = 24 -- genau der Wert,
# an dem die Grenze in last_sunday() sitzt. Der letzte Sonntag im Maerz 2030
# ist erst der 31., die Sommerzeit hat also noch NICHT begonnen.
#
# Mit `recent >= 25` liefert last_sunday korrekt 31 -> noch CET (+1)
# -> 07 UTC ist 08 lokal -> abgelehnt.
#
# Mit einem `recent >= 24` liefert sie 24, der Tag gilt faelschlich als nach
# der Umstellung -> CEST (+2) -> 09 lokal -> erlaubt. Ohne diesen Fall bliebe
# dieser Off-by-one unbemerkt.
mock "time" {
  data = {
    now = {
      year    = 2030
      month   = 3
      day     = 25
      hour    = 7
      weekday = 1
    }
  }
}

global "identity" { value = {} }
global "token"    { value = {} }

test {
  rules = {
    main             = false
    within_workhours = false
  }
}
