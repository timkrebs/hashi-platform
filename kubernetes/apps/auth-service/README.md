# auth-service

Issues short-lived RS256 JWTs. Credentials are verified against Vault's
userpass auth; the signature is produced by Vault's Transit engine, so the
private key is generated inside Vault and never leaves it.

This service stores no passwords, holds no signing key, and carries no
long-lived credential of its own.

## Why it is built this way

**The service never calls Vault.** The Vault Secrets Operator authenticates
with *this namespace's* ServiceAccount, reads the one KV path its Vault policy
allows, and writes the result into an ordinary Kubernetes Secret. The pod
mounts that Secret as files. Vault is therefore not on the request path: if
Vault is down, logins keep working from what is already on disk.

The honest cost: the signing key now exists outside Vault — in etcd and in this
pod's memory. EKS envelope-encrypts Secrets with KMS, and a rotation restarts
the Deployment, but a compromised pod holds a real signing key and can mint
tokens for as long as it runs. Signing through Vault's Transit engine avoided
exactly that, at the price of a Vault round trip on every login and a hard
runtime dependency. This is that trade taken deliberately.

**No passwords are stored here.** The user list is bcrypt hashes, synced from
Vault. `Load` refuses to start if any entry is not a bcrypt hash, so a
plaintext password is found by the pipeline rather than by a user.

**Verification is decentralised.** Other services fetch
`/.well-known/jwks.json`, cache it, and verify locally. An auth service that
must be asked about every request is a single point of failure for the cluster.

**The `kid` is derived, not configured.** It is the RFC 7638 thumbprint of the
public key, so it changes exactly when the key changes — a rotation cannot
reuse a `kid` and leave verifiers matching a token against the wrong key.

## The secret chain

```
VaultStaticSecret ──▶ Vault Secrets Operator
                         │  logs in as ServiceAccount auth-service
                         │  (VaultAuth, Vault namespace hp-dev-backend)
                         ▼
                      kv/auth-service/config
                         │  signing-key  (RSA PEM)
                         │  users        (JSON: username -> bcrypt hash)
                         ▼
              Secret auth-service-secrets
                         │
                         ▼  mounted read-only
              /etc/auth-service/secrets/
```

`deploy/vault.yaml` holds all three custom resources, and they are all
namespace-local. The operator is installed with `defaultVaultConnection` and
`defaultAuthMethod` disabled on purpose: a cluster-wide Vault identity would
reach everything any policy allows, while this way the boundary stays per
namespace.

The Vault side is Terraform in
[`config/vault/kubernetes-auth.tf`](../../../config/vault/kubernetes-auth.tf):
the `kubernetes` auth backend, a read-only policy on one KV path, and a role
bound to `ServiceAccount auth-service` in `namespace auth-service`. Both bounds
matter — without `bound_service_account_namespaces` any namespace could create
a ServiceAccount with this name and read the key.

### Rotation

Write a new key to Vault; the operator notices within `refreshAfter` and
restarts the Deployment through `rolloutRestartTargets`. The new pod publishes
a new `kid`.

Tokens signed by the old key stop verifying at that moment. The TTL is short,
which bounds the damage; if that is not good enough, publish the previous key
in JWKS for one TTL's worth of overlap.

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
| `GET /healthz` | liveness — does **not** depend on the secret |
| `GET /readyz` | readiness — true once the secret is synced and parsed |

Two listeners rather than one: metrics expose internal timing and `/readyz`
reveals dependency state, and neither belongs on the port that serves
untrusted callers.

**Liveness must not depend on the secret.** If it did, a sync problem would
make Kubernetes restart every auth pod instead of taking them out of rotation.
Readiness is where the dependency belongs: an unready pod leaves the Service
endpoints; an unhealthy one is restarted.

The pod starts before the operator has written the Secret — Argo CD applies the
Deployment and the `VaultStaticSecret` in the same wave. The listeners come up
first and the service reports unready until the files appear, so the startup
probe does not read the sync window as a dead process.

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

`auth_secret_loaded` is the same signal `/readyz` reports, as a number to alert
on. `auth_secret_loads_total{result="error"}` rising while
`auth_secret_loaded` stays 1 means rotation is failing silently — the service
keeps working on the key it already has, and nothing else would tell you.

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

- [ ] `terraform apply` on `config/vault`
- [ ] the Vault Secrets Operator is running (`gitops/apps/vault-secrets-operator.yaml`)
- [ ] the KV secret exists — it is written out of band, never by Terraform,
      because a signing key in Terraform state defeats the point:
      ```bash
      openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out signing.pem
      htpasswd -bnBC 12 "" 'the-password' | tr -d ':\n'   # bcrypt hash
      vault kv put -namespace=hp-dev-backend kv/auth-service/config \
        signing-key=@signing.pem \
        users='{"dev1":"<bcrypt-hash>"}'
      rm signing.pem
      ```
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
performs a bcrypt comparison and an RSA signature. Both are deliberately
expensive, which is what makes the endpoint worth a per-IP limit before
anything real depends on it.

**Tokens cannot be revoked.** That is inherent to stateless JWTs. The TTL is
the mitigation; a denylist would mean asking a central service on every
request, which is the design this deliberately avoids.
