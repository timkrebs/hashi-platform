#!/usr/bin/env bash
# Smoke test for the built container image.
#
# Runs the image exactly as shipped -- distroless, non-root, read-only root
# filesystem -- with no synced secret. That is the point: it proves the binary
# actually starts in that image, and that the liveness/readiness split behaves
# correctly while the Vault Secrets Operator has not written the Secret yet,
# which is exactly the state every pod passes through on startup.
#
# Usage: ci/smoke.sh <image>
set -euo pipefail

IMAGE="${1:?usage: ci/smoke.sh <image>}"
NAME="auth-service-smoke-$$"

cleanup() {
  echo "--- container logs ---"
  docker logs "${NAME}" 2>&1 | tail -30 || true
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() { echo "::error::$*"; exit 1; }

echo "starting ${IMAGE}"
docker run -d --name "${NAME}" \
  --read-only \
  --user 65532:65532 \
  --cap-drop ALL \
  -p 18080:8080 -p 19090:9090 \
  -e SECRETS_DIR=/nonexistent \
  -e SECRETS_RETRY=2s \
  "${IMAGE}" >/dev/null

# 1. Liveness must come up WITHOUT the secret. If it did not, the startup
#    probe would kill the pod during the operator's sync window.
echo "waiting for /healthz"
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://localhost:19090/healthz || true)
  [ "${code}" = "200" ] && break
  if [ "${i}" = "30" ]; then fail "/healthz never returned 200 (last: ${code:-none})"; fi
  sleep 1
done
echo "  /healthz 200"

# 2. Readiness must be false: there is no secret. A service that reports
#    ready here would take traffic it cannot serve.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:19090/readyz || true)
[ "${code}" = "503" ] || fail "/readyz returned ${code}, want 503 without the synced secret"
echo "  /readyz 503 as expected"

# 3. Metrics that exist before any request. A counter whose labels are known
#    in advance must already be published, or a dashboard on a fresh pod shows
#    "No data" instead of zero.
body=$(curl -s --max-time 5 http://localhost:19090/metrics || true)
grep -q '^auth_secret_loaded 0$' <<<"${body}" \
  || fail "/metrics does not report auth_secret_loaded=0 before the sync"
grep -q '^auth_tokens_issued_total{result="denied"} 0$' <<<"${body}" \
  || fail "/metrics does not pre-initialise auth_tokens_issued_total"
echo "  /metrics pre-initialises its known series"

# 4. The public endpoint must degrade, not crash. Without the secret a token
#    request
#    is 503 -- never a 500 and never a panic that takes the process down.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  -X POST http://localhost:18080/v1/token \
  -H 'Content-Type: application/json' \
  -d '{"username":"dev1","password":"x"}' || true)
[ "${code}" = "503" ] || fail "POST /v1/token returned ${code}, want 503 without the synced secret"
echo "  POST /v1/token 503 as expected"

# 5. A malformed body must be rejected before anything else happens.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  -X POST http://localhost:18080/v1/token -d 'not json' || true)
[ "${code}" = "400" ] || fail "malformed body returned ${code}, want 400"
echo "  malformed body 400 as expected"

# 6. The middleware must actually have recorded those two requests. Asserting
#    this after exercising the endpoints proves instrumentation works
#    end to end, rather than that a symbol is registered somewhere.
body=$(curl -s --max-time 5 http://localhost:19090/metrics || true)
grep -q '^auth_http_requests_total{method="POST",route="/v1/token",status="4xx"} 1$' <<<"${body}" \
  || fail "/metrics did not record the malformed-body request"
grep -q '^auth_http_requests_total{method="POST",route="/v1/token",status="5xx"} 1$' <<<"${body}" \
  || fail "/metrics did not record the Vault-unavailable request"
echo "  /metrics recorded both requests with the route label, not the path"

# 7. The process must still be running after all of that.
[ "$(docker inspect -f '{{.State.Running}}' "${NAME}")" = "true" ] \
  || fail "container exited during the smoke test"
echo "  container still running"

echo "smoke test passed"
