# Loeschen und Metadaten-Operationen sind ebenfalls ausgenommen. Der Pfad
# zeigt hier bewusst auf metadata/ statt data/.
global "request" {
  value = {
    operation = "delete"
    path      = "kv/metadata/Payments/APP/whatever"
  }
}

test {
  rules = {
    main        = true
    is_kv_write = false
  }
}
