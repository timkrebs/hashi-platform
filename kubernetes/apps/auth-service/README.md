# auth-service

Issues short-lived RS256 JWTs. Credentials are verified against Vault's
userpass auth; the signature is produced by Vault's Transit engine, so the
private key is generated inside Vault and never leaves it.

This service stores no passwords, holds no signing key, and carries no
long-lived credential of its own.

## Why it is built this way

**The signing key lives in Transit, not in a file.** The usual pattern —
mount a key from KV and sign locally — means a compromised pod can mint valid
tokens for as long as it keeps the key, including after it is stopped. With
Transit the pod sends the bytes to sign and gets a signature back; take its
Vault token away and it can issue nothing.

The honest cost: Vault is now a hard runtime dependency for *issuing* tokens.
*Verifying* them is unaffected — verifiers use the public key from JWKS and
never call Vault or this service.

**Credentials are checked by Vault.** No password hashing, no user table, no
credential store to leak. Adding a user is `vault write
auth/userpass/users/...`, not a migration.

**Verification is decentralised.** Other services fetch
`/.well-known/jwks.json` once, cache it, and verify locally. An auth service
that must be asked about every request is a single point of failure for the
whole cluster.

## The Vault chain

```
Pod                    ServiceAccount token (projected, short-lived)
  │
  ▼
Vault Agent init       POST auth/kubernetes/login  ──▶ Vault
  │                    Vault calls TokenReview on the API server to check it
  │                    (needs system:auth-delegator on Vault's own SA)
  ▼
/vault/secrets/token   Vault token with policy "auth-service", TTL 1h
  │                    sidecar renews it and rewrites the file
  ▼
auth-service           POST transit/sign/auth-service-jwt   → signature
                       GET  transit/keys/auth-service-jwt   → public key
```

Every piece is Terraform in [`config/vault/kubernetes-auth.tf`](../../../config/vault/kubernetes-auth.tf):
the `kubernetes` auth backend, the Transit mount and RSA key, the policy, and
the role binding `ServiceAccount auth-service` in `namespace auth-service`.
Both bounds matter — without `bound_service_account_namespaces` any namespace
could create a ServiceAccount with this name and sign tokens.

## Endpoints

Public (`:8080`):

| | |
|---|---|
| `POST /v1/token` | `{"username","password"}` → `{"access_token","token_type","expires_in"}` |
| `GET /.well-known/jwks.json` | public keys, all versions |

Admin (`:9090`, never published outside the cluster):

| | |
|---|---|
| `GET /metrics` | Prometheus |
| `GET /healthz` | liveness — does **not** touch Vault |
| `GET /readyz` | readiness — does |

Two listeners rather than one: metrics expose internal timing and `/readyz`
reveals dependency state, and neither belongs on the port that serves
untrusted callers.

**Liveness must not depend on Vault.** If it did, a Vault restart would make
Kubernetes kill every auth pod at once and turn a short blip into an outage.
Readiness is where the dependency belongs: an unready pod leaves the Service
endpoints; an unhealthy one is restarted.

## Verifying a token elsewhere

```
GET https://auth-service.auth-service.svc.cluster.local:8080/.well-known/jwks.json
```

Match the token's `kid` against the JWKS entry, verify RS256, then check `iss`,
`aud` and `exp`. Cache the JWKS and refetch on an unknown `kid` — that is what
makes key rotation non-disruptive.

Rotation is a Vault operation:

```bash
vault write -f -namespace=hp-dev-backend transit/keys/auth-service-jwt/rotate
```

Old versions stay published, so tokens signed before the rotation keep
verifying until they expire.

## Configuration

All from the environment; the service refuses to start on anything it cannot
validate. `TOKEN_TTL` is capped at one hour in code, because these tokens
cannot be revoked once issued — the TTL is the only thing bounding a leak.

`SHUTDOWN_GRACE` must stay below the Deployment's
`terminationGracePeriodSeconds`, or the grace period is decorative and
in-flight requests are cut off by SIGKILL.

## Observability

Logs are JSON on stdout — Alloy ships them to Loki, query with
`{namespace="auth-service"}`. No username, token or Authorization header is
ever logged.

Metrics are scraped through the ServiceMonitor in `deploy/`. Every label is
bounded; the `route` label is the registered pattern, never the request path,
because a path label creates one time series per URL.

`auth_vault_up` is the same signal `/readyz` reports, as a number to alert on.
`auth_vault_request_duration_seconds{operation="transit_sign"}` is the one to
watch — signing is on the critical path of every login.

## Build and deploy

`.github/workflows/services.yml` does it:

```
discover -> fmt -> vet -> test -> build -> container-test -> scan -> push -> bump
```

`fmt` also checks that `go mod tidy` is a no-op. `vet` runs staticcheck.
`test` adds `-race` and `govulncheck`. The image is built **once** and the same
tarball is then smoke-tested, scanned by Trivy and pushed — rebuilding between
stages would mean scanning something other than what ships.

GHCR rather than ECR for two reasons: an ECR address contains the AWS account
ID and this repository is public, and pushing to GHCR needs only the built-in
`GITHUB_TOKEN` with `packages: write` — no OIDC against AWS, which this account
blocks. A public repository's packages can be public, so the kubelet pulls them
with no `imagePullSecret`.

On a push to `main` the image is tagged `sha-<12>` and the `bump` stage writes
that tag into `deploy/kustomization.yaml` and commits it with `[skip ci]`. Argo
CD deploys what is in git, so that commit *is* the deployment. The manifests
never pin `latest`: a moving tag makes a rollback guesswork.

Locally:

```bash
make check                          # fmt, vet, test
make image
ci/smoke.sh ghcr.io/timkrebs/auth-service:v0.1.0
```

`ci/smoke.sh` runs the image as shipped — distroless, non-root, read-only root
filesystem — with no Vault anywhere, and asserts that `/healthz` answers, that
`/readyz` does not, and that `POST /v1/token` degrades to 503 rather than
crashing. The same script is what the pipeline runs.

## Before this runs

- [ ] `terraform apply` on `config/vault` — the `kubernetes` auth backend,
      Transit mount, policy and role do not exist yet
- [ ] a push to `main` has run the pipeline once, so the image exists and
      `deploy/kustomization.yaml` pins its tag
- [ ] `deploy/vault-ca.pem` still matches the cluster:
      ```bash
      kubectl -n vault get secret vault-tls -o jsonpath='{.data.ca\.crt}' \
        | base64 -d | diff - deploy/vault-ca.pem
      ```
- [ ] pod slots: the cluster runs near its ceiling (17 per `t3.medium`), and
      this adds two pods

## Known gaps

**The NetworkPolicy is not enforced.** The AWS VPC CNI only applies
NetworkPolicies when its nodeagent runs with `--enable-network-policy=true`;
on this cluster it is `false`. Kubernetes accepts the object without
complaint, so it looks like traffic is restricted when it is not. Enable it
through the `vpc-cni` addon configuration (`enableNetworkPolicy = "true"`) in
`infra/modules/aws-eks-cluster`.

**No rate limiting.** `POST /v1/token` is an unauthenticated endpoint that
performs an RSA signature. Both make it worth a per-IP limit before anything
real depends on it.

**Tokens cannot be revoked.** That is inherent to stateless JWTs. The TTL is
the mitigation; a denylist would mean asking a central service on every
request, which is the design this deliberately avoids.
