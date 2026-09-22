#!/usr/bin/env bash
#
# Schreibt konforme und nicht konforme Secrets gegen ein echtes Vault und
# zeigt, was die EGP damit macht.
#
# Erwartet VAULT_ADDR und VAULT_TOKEN in der Umgebung. Beides wird hier
# bewusst nicht gesetzt, nicht abgefragt und nirgends geloggt.
#
#   export VAULT_ADDR=https://<vault>:8200
#   export VAULT_TOKEN=<token>
#   ./scripts/verify.sh hp-dev-backend
#
# Das Skript raeumt hinter sich auf: jedes Secret, das es anlegt, loescht es
# am Ende wieder -- inklusive Metadaten, sonst bleiben die Versionen stehen.
set -euo pipefail

NAMESPACE="${1:-hp-dev-backend}"
MOUNT="${MOUNT:-kv}"
POLICY="kv-naming-team-app-name-secret"

: "${VAULT_ADDR:?VAULT_ADDR ist nicht gesetzt}"
: "${VAULT_TOKEN:?VAULT_TOKEN ist nicht gesetzt}"
export VAULT_NAMESPACE="$NAMESPACE"

command -v vault >/dev/null || { echo "vault CLI nicht gefunden" >&2; exit 1; }

# Aufraeumliste, damit auch ein Abbruch nichts liegen laesst.
CREATED=()
cleanup() {
  [ ${#CREATED[@]} -eq 0 ] && return 0
  echo
  echo "== Aufraeumen =="
  for p in "${CREATED[@]}"; do
    vault kv metadata delete "${MOUNT}/${p}" >/dev/null 2>&1 && echo "  geloescht: ${p}" || true
  done
}
trap cleanup EXIT

# Unter soft-mandatory geht der Schreibzugriff durch und der Verstoss steht nur
# im Audit-Log. Die Erwartung haengt also am Enforcement-Level -- ohne diese
# Abfrage wuerde das Skript im Einfuehrungsmodus reihenweise "Fehler" melden,
# die keine sind.
LEVEL="$(vault read -field=enforcement_level "sys/policies/egp/${POLICY}" 2>/dev/null || echo "NICHT-DEPLOYT")"
echo "== EGP ${POLICY} in ${NAMESPACE}: ${LEVEL} =="
if [ "$LEVEL" = "NICHT-DEPLOYT" ]; then
  echo "   Die Policy ist in diesem Namespace nicht vorhanden. Erst deployen," >&2
  echo "   sonst geht unten alles durch und beweist nichts." >&2
  exit 1
fi
echo

if [ "$LEVEL" = "hard-mandatory" ]; then
  EXPECT_BAD="abgelehnt (403)"
else
  EXPECT_BAD="durchgelassen, Verstoss nur im Audit-Log"
fi

# try <erwartung> <pfad> <key=value>...
try() {
  local expect="$1" path="$2"; shift 2
  local out rc
  set +e
  out="$(vault kv put "${MOUNT}/${path}" "$@" 2>&1)"; rc=$?
  set -e

  if [ $rc -eq 0 ]; then
    CREATED+=("$path")
    if [ "$expect" = "ok" ]; then
      printf '  OK       %s\n' "$path"
    else
      printf '  %s  %s\n' "$([ "$LEVEL" = hard-mandatory ] && echo 'UNERWARTET' || echo 'zugelassen')" "$path"
    fi
  else
    if [ "$expect" = "ok" ]; then
      printf '  FEHLER   %s -- haette durchgehen muessen:\n' "$path"
      printf '%s\n' "$out" | sed 's/^/             /'
    else
      printf '  403      %s\n' "$path"
      printf '%s\n' "$out" | grep -io "${POLICY}[^\"]*" | head -1 | sed 's/^/             /' || true
    fi
  fi
}

echo "== Konform (muss durchgehen) =="
try ok "backend/auth-service/signing-secret" APP_SIGNING_KEY=xxx APP_DB_PASSWORD=yyy
echo
echo "== Nicht konform (erwartet: ${EXPECT_BAD}) =="
try bad "backend/Auth-Service/signing-secret" APP_TOKEN=xxx   # Grossbuchstaben im Pfad
try bad "payments/checkout/db-secret"         APP_TOKEN=xxx   # unbekanntes Team
try bad "backend/auth-service/signing"        APP_TOKEN=xxx   # Suffix fehlt
try bad "backend/auth_service/signing-secret" APP_TOKEN=xxx   # Unterstrich im Pfad
try bad "api-key"                             APP_TOKEN=xxx   # zu wenige Segmente (Altbestand)
try bad "backend/auth-service/signing-secret" app_token=xxx   # Key klein
try bad "backend/auth-service/signing-secret" DB_PASSWORD=xxx # Key ohne APP_
echo
echo "== Lesen bleibt unberuehrt =="
vault kv get "${MOUNT}/backend/auth-service/signing-secret" >/dev/null 2>&1 \
  && echo "  OK       Lesen des konformen Secrets" \
  || echo "  FEHLER   Lesen schlug fehl"
