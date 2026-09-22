# Anforderung 1: Metadaten-Operationen bleiben unberuehrt -- und zwar auch die
# SCHREIBENDEN. `vault kv metadata put` ist ein update auf kv/metadata/<pfad>,
# faellt also in write_operations und wird nur durch die has_prefix-Pruefung
# auf kv/data/ aus dem Geltungsbereich gehalten.
#
# Der Pfad verletzt die Konvention absichtlich. Ohne diesen Fall koennte die
# Bereichspruefung wegfallen und das Setzen von Metadaten an Altbestand-Pfaden
# waere plötzlich verboten, ohne dass ein Test es merkt.
global "request" {
  value = {
    operation = "update"
    path      = "kv/metadata/api-key"
    data      = { max_versions = 5 }
  }
}

test {
  rules = {
    main        = true
    is_kv_write = false
  }
}
