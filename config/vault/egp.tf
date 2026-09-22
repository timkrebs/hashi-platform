# Endpoint Governing Policy: Namenskonvention fuer die KV-v2-Mounts der Teams.
#
# Die Policy liegt als eigene Datei unter policies/ und wird hier nur
# eingelesen. Das ist Absicht: `sentinel test` laeuft gegen genau dieselbe
# Datei, die hier deployt wird. Waere der Sentinel-Code hier als Heredoc
# eingebettet, koennten getestete und ausgerollte Fassung auseinanderlaufen,
# ohne dass es auffaellt.

locals {
  # Beide Team-Namespaces bekommen dieselbe Policy. Eine EGP gilt immer nur in
  # dem Namespace, in dem sie geschrieben wird -- es gibt keine Vererbung nach
  # unten, also braucht es pro Namespace eine Ressource.
  kv_naming_namespaces = {
    backend  = vault_namespace.backend.path_fq
    frontend = vault_namespace.frontend.path_fq
  }
}

resource "vault_egp_policy" "kv_naming" {
  for_each = local.kv_naming_namespaces

  namespace = each.value

  # Der Name steht im 403, den ein Entwickler zu sehen bekommt. Er nennt
  # deshalb die geforderte Pfadform statt nur "policy denied".
  name = "kv-naming-team-app-name-secret"

  # Relativ zum Namespace. Deckt jeden Schreibzugriff auf Secret-Inhalte ab;
  # kv/metadata/* bleibt bewusst draussen, und die Policy prueft den Praefix
  # zusaetzlich selbst, damit sie auch bei einem weiter gefassten paths-Wert
  # nicht ueber ihren Geltungsbereich hinausgreift.
  paths = ["kv/data/*"]

  # UMSTELLUNG AUF DURCHSETZEN: diese eine Zeile.
  #
  #   soft-mandatory  Verstoss wird protokolliert, der Schreibzugriff geht
  #                   durch. In diesem Modus einfuehren, bis die Logs zeigen,
  #                   dass nichts Unerwartetes anschlaegt.
  #   hard-mandatory  Verstoss wird mit 403 abgelehnt.
  #
  # Vorher pruefen, dass config/vault selbst konform ist -- ein Apply schreibt
  # die Secrets unten neu, und unter hard-mandatory wuerde die Pipeline daran
  # scheitern.
  enforcement_level = var.kv_naming_enforcement_level

  policy = file("${path.module}/policies/kv-naming.sentinel")
}

# ---------------------------------------------------------------------------
# Geschaeftszeiten-Fenster auf den Backend-Secrets.
#
# Bewusst eng: nur kv/data/backend/* und nur im Namespace hp-dev-backend.
# Diese Policy kennt keinen Operationsfilter -- sie lehnt auch Lesezugriffe ab.
# Auf "*" gehaengt wuerde sie damit den halben Cluster abends stilllegen:
# Token-Renewals, sys/*, den Prometheus-Scrape. Das Fenster auszuweiten ist
# deshalb eine eigene Entscheidung und kein Nebeneffekt.
#
# Maschinen sind in der Policy selbst ausgenommen, nicht hier: ueber den
# Auth-Mount-Typ (kubernetes, approle, aws, jwt) und ueber die Policy
# vault-automation unten. Der Vault Secrets Operator und der Agent Injector
# fallen damit heraus -- sie haben keine Buerozeiten.
resource "vault_egp_policy" "business_hours" {
  namespace = vault_namespace.backend.path_fq

  name  = "business-hrs-europe-berlin"
  paths = ["kv/data/backend/*"]

  # Wie bei kv-naming: erst beobachten, dann durchsetzen. Eine Zeile.
  enforcement_level = var.business_hours_enforcement_level

  policy = file("${path.module}/policies/business-hrs.sentinel")
}

# Marker-Policy fuer die Ausnahme. Sie gewaehrt nichts -- sie existiert nur,
# damit ein Token sie tragen und damit von der Zeitpruefung ausgenommen werden
# kann. Gedacht fuer den Pipeline-Token und fuer Break-glass.
#
# Ohne diese Ressource waere der Name in exempt_policies ein Verweis ins
# Leere und die Ausnahme nicht nutzbar.
resource "vault_policy" "automation" {
  namespace = vault_namespace.backend.path_fq
  name      = "vault-automation"

  policy = <<-EOT
    # Absichtlich ohne Regeln. Diese Policy ist eine Markierung, kein
    # Berechtigungssatz: business-hrs-europe-berlin nimmt jeden Token aus,
    # der sie traegt. Zugriffsrechte kommen weiterhin aus einer zweiten,
    # eigenen Policy.
  EOT
}
