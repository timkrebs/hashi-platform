# Layer 3 — Vault configuration (minimal slice)

Turns Vault into a signing authority for Boundary SSH sessions. This is the
**first slice** of Layer 3, deliberately minimal because Layer 7 (Boundary) is
being built ahead of Layers 4–6:

- **SSH client-signer engine** (`ssh-client-signer`): CA generated inside Vault,
  signs short-lived (5-minute) user certificates for `ec2-user`
- **`boundary-controller` policy**: token self-management for Boundary's
  credential store
- **`ssh-signer` policy**: sign with the `boundary-client` role, nothing else

Still to come when their consumers land (the plan expects this layer to be
revisited): JWT auth + `nomad-workloads` role (Layer 5), mesh PKI for the
Consul Connect CA (Layer 4), AWS/database/KV engines (Layer 6). Audit:
HCP Vault Dedicated manages audit devices itself — streaming to CloudWatch is
configured on the *cluster* (Layer 2's `audit_log_config`), planned with the
observability work in Layer 8.

## How it authenticates

The workspace runs in **agent mode** (in-VPC agent from `1-tfc-agent`) because
the Vault API only exists on the private endpoint. Each run mints a fresh
6-hour `hcp_vault_cluster_admin_token` — no stored Vault credential anywhere.

## Run

Depends on: `2-vault-cluster` applied, the agent online. PR → merge → confirm
apply in workspace `3-vault-config`.

## Definition of Done

```sh
vault read ssh-client-signer/config/ca   # via a private-subnet host
```
returns the CA public key, and signing a test key with role `boundary-client`
succeeds. (Both also implicitly proven by Layer 7's end-to-end session.)
