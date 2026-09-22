# Vault EGP policies

Two Endpoint Governing Policies for the team namespaces. This is a different
Sentinel runtime from `infra/policies/`: those run inside HCP Terraform against
`tfplan/v2`, these run inside Vault against the `request`, `identity` and
`token` globals. The two suites share nothing and are tested separately.

| Policy | What it does | Scope |
|---|---|---|
| `kv-naming-team-app-name-secret` | naming convention for KV v2 paths and keys | `kv/data/*`, both team namespaces |
| `business-hrs-europe-berlin` | Mon-Fri 09:00-17:00 Europe/Berlin | `kv/data/backend/*`, backend namespace only |

Both ship at `soft-mandatory`.

## Root tokens are not governed

**Neither policy applies to a root token.** HashiCorp states it plainly: *"Like
with ACLs, root tokens are not subject to Sentinel policy checks."* Writing a
non-conforming secret with the root token succeeds, at any enforcement level,
and nothing appears in the trace because the policy is never evaluated.

This is not a gap to work around — root token generation deliberately cannot be
governed by an EGP, because it is the way back in after a misconfigured one
locks everyone out.

It does mean two things in practice. Testing enforcement requires a non-root
token: `vault token create -policy=dev -ttl=2m` and then writing with that.
And the pipeline token (`display_name` `token-terraform`) currently carries the
`root` policy, so `config/vault` applies are exempt — convenient, but it also
means CI cannot prove the policies work.

---

# kv-naming-team-app-name-secret

A Vault Enterprise Endpoint Governing Policy that enforces a naming convention
on the KV v2 mounts in the team namespaces. It is a different Sentinel runtime
from the policies in `infra/policies/`: those run inside HCP Terraform against
`tfplan/v2`, these run inside Vault against the `request` global. The two
suites share nothing and are tested separately.

## The convention

Write path, relative to the mount:

```
kv/data/<team>/<app>/<name>-secret
```

| Part | Rule |
|---|---|
| `team` | one of `backend`, `frontend`, `platform` |
| `app` | `a-z`, `0-9`, hyphens; no leading, trailing or doubled hyphen |
| `name` | same, and must end in `-secret` |
| segments | exactly three |

Keys inside the secret: `UPPER_SNAKE_CASE` with an `APP_` prefix, characters
`A-Z`, `0-9` and underscore, no trailing or doubled underscore. A secret with
no keys at all is refused.

```
kv/data/backend/auth-service/signing-secret   APP_SIGNING_KEY   accepted
kv/data/frontend/web/api-token-secret         APP_TOKEN         accepted
kv/data/payments/checkout/db-secret           APP_TOKEN         team unknown
kv/data/backend/auth-service/signing          APP_TOKEN         suffix missing
kv/data/backend/auth-service/signing-secret   app_token         key not UPPER_SNAKE
kv/data/backend/auth-service/signing-secret   DB_PASSWORD       key prefix missing
```

## What it does not touch

Only `create`, `update` and `patch` under `kv/data/`. Reads, lists, deletes and
everything under `kv/metadata/` pass untouched, so secrets that predate the
convention stay readable and deletable. `patch` is in scope because a KV v2
patch adds keys to an existing secret and can introduce a non-conforming key
just as a full write can.

## Running the tests

```bash
cd config/vault/policies
sentinel test            # 24 fixtures
sentinel fmt -check -write=false ./kv-naming.sentinel
```

`make policy-test` from the repository root runs this suite alongside the
HCP Terraform one.

The fixtures mock Vault's `request` global directly — `global "request" { value
= {...} }`, not a `mock` block, because `request` is injected by Vault rather
than imported.

## Deploying

`config/vault/egp.tf` creates one `vault_egp_policy` per team namespace. An EGP
only applies in the namespace it was written to; there is no inheritance, which
is why there are two resources and not one.

The Terraform reads `policies/kv-naming.sentinel` with `file()` instead of
embedding the policy as a heredoc. That keeps one copy, so what `sentinel test`
checks is byte-for-byte what gets deployed.

Deployment runs through the normal pipeline — the `hashi-platform-vault`
workspace, planned and applied by `.github/workflows/terraform.yml`.

## Switching to hard-mandatory

It ships at `soft-mandatory`: violations are logged, the write still succeeds.
That is the only way to find out what the rule would break before it breaks it.
Watch the Vault audit log, then change one value:

```
kv_naming_enforcement_level = "hard-mandatory"
```

in the `hashi-platform-vault` workspace, and apply.

Before you do, make sure everything that writes to these mounts is conforming —
including `config/vault` itself. A Terraform apply rewrites the demo secrets on
every run, so a non-conforming one there turns the pipeline red.

## Adding a team

Two edits, both required:

1. `kv-naming.sentinel`, the alternation in `path_pattern`:
   `(backend|frontend|platform|newteam)`
2. `test/kv-naming/`, a passing fixture for the new team.

Step 2 is not optional. `fail-path-unknown-team.hcl` is the only fixture that
pins the alternation; without a matching positive case, opening it up to
`([a-z]+)` would still leave the suite green for the wrong reason.

## Verifying against a real Vault

```bash
export VAULT_ADDR=https://<vault>:8200
export VAULT_TOKEN=<token>
./scripts/verify.sh hp-dev-backend
```

It writes one conforming and seven non-conforming secrets, prints what Vault
did with each, and deletes everything it created — metadata included. It reads
the deployed enforcement level first and adjusts its expectations, so it does
not report false failures while the policy is still in soft-mandatory.

## Notes from building it

Three things about Sentinel that the policy depends on, each verified against
the CLI rather than assumed:

- **`matches` searches for a substring.** `"PREFIX/kv/data/x-secret/SUFFIX"
  matches "kv/data/x-secret"` is true. Both patterns are anchored with `^` and
  `$`; four fixtures exist only to keep those anchors in place.
- **`all` over an empty collection is true.** An empty secret would therefore
  satisfy the key rule without a single key being examined. `data_present` is a
  separate rule that closes this, and `fail-empty-data.hcl` proves the hazard is
  real rather than theoretical.
- **A rule that is never evaluated does not appear in the trace, and
  `sentinel test` can only assert on rules that are in it.** `main` therefore
  forwards to `enforced` rather than being the `rule when` itself — otherwise
  the most important property of this policy, "a read is allowed however the
  secret is named", would not be assertable.

The suite was checked by mutation: twelve deliberate breakages of the policy
(dropping an anchor, `all` to `any`, removing `patch`, widening the team
alternation, removing the undefined guard, dropping the `kv/data/` scope check)
were each applied in turn, and every one of them is caught by at least one
fixture.

---

# business-hrs-europe-berlin

Denies requests outside Monday to Friday, 09:00-17:00 Europe/Berlin.

## Why it computes the timezone itself

Sentinel's `time` import is documented as UTC and offers **no timezone
conversion at all**. `time.now.hour >= 9` therefore means 09:00 UTC, which is
11:00 in Berlin in summer and 10:00 in winter — a window that silently moves by
an hour twice a year, and that is wrong right now: at 09:17 CEST the UTC hour
is 7.

So the policy derives the offset. CET is UTC+1, CEST is UTC+2, and the EU
switches on the last Sunday in March at 01:00 UTC and back on the last Sunday
in October. The last Sunday of a month always falls between the 25th and the
31st, so `last_sunday()` finds it from the current day and weekday alone:
`day - weekday` is the most recent Sunday, plus seven if that is still before
the 25th.

Adding the offset can cross midnight, so the weekday is corrected too. It makes
no difference while the window is 09:00-17:00 — it will the moment anyone
widens it.

## Why machines are exempt, and why through `token`

A Vault installation is mostly machines, and they do not keep office hours. Two
exemptions, both in the policy:

- **`token.path`** starting with `auth/kubernetes/`, `auth/approle/`,
  `auth/aws/` or `auth/jwt/`. It is "the request path that resulted in creation
  of this token", so it names the auth mount the token came from.
  `auth/userpass/` is deliberately absent — that is how humans log in here.
- **the policy `vault-automation`**, created by `egp.tf` as a marker that grants
  nothing. Attach it to a break-glass token and the time check is skipped.

The first version of this used `identity.entity.aliases`, and it broke in
production: `identity` is a **conditionally present namespace**, a token with no
entity does not get one, and Sentinel then aborts with

```
unknown identifier accessed: identity
```

instead of returning a decision. `else` does not help — it catches an undefined
*value*, not an absent *identifier*; `identity.entity.aliases else []` and
`identity else null` fail identically. The unit tests missed it because the
fixtures mocked `global "identity" { value = {} }`, which makes the identifier
exist.

`token` is conditionally present as well — the properties documentation notes it
is absent while logging in — so **this policy must only ever be attached to
authenticated paths**. `kv/data/*` is one; an `auth/*/login` path would break it
the same way.

## Scope

`kv/data/backend/*` in `hp-dev-backend`, and nothing else. The policy has no
operation filter, so it denies **reads** as well. On `*` it would take down
token renewals, `sys/*` and the Prometheus scrape after 17:00. Widening it is a
decision to make on purpose.

EGPs do not apply to root tokens, and root token generation cannot be governed
by an EGP, so a mistake here is recoverable.

## Tests

22 fixtures: both hour boundaries in summer *and* winter (the winter cases are
what pin the timezone — 08:00 UTC is 09:00 local in January and 10:00 in July),
all four weekday boundaries, both DST changeovers, the `day - weekday == 24`
edge in `last_sunday()`, the midnight rollover, and all four exemption paths.

Note that `time` is an **import**, so fixtures mock it with
`mock "time" { data = { now = {...} } }`. `identity` and `token` are globals and
use `global "identity" { value = {...} }`. Getting this backwards is quiet: the
policy then reads the real clock, and the passing fixtures go green for the
wrong reason whenever the suite happens to run during business hours.

Checked by mutation: sixteen deliberate breakages — dropping either hour bound,
an off-by-one on the closing hour, allowing Saturday or Sunday, ignoring the
offset, pinning it to summer or winter, removing the rollover, the
`last_sunday()` off-by-one, swapping March and October, disabling or inverting
the exemption, exempting `userpass`, and removing either `else` guard — and
every one is caught by at least one fixture.
