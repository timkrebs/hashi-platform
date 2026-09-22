# Anforderung 1: Lesen bleibt unberuehrt, damit Altbestand lesbar bleibt.
# Der Pfad hier verletzt jede einzelne Regel -- und muss trotzdem durchgehen.
global "request" {
  value = {
    operation = "read"
    path      = "kv/data/Payments/APP/whatever"
  }
}

test {
  rules = {
    main        = true
    is_kv_write = false
  }
}
