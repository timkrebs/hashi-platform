# Layer 7 — Boundary

Identity-based access to private nodes — no bastion, no SSH keys, no inbound
rules. Built ahead of Layers 4–6 (with a minimal Layer 3 slice) so the access
path exists before the platform runtime lands.

**Session path:** operator → HCP-managed ingress worker → self-managed egress
worker (outbound-only, private subnet) → target. **Credential path:** Boundary
generates an ed25519 keypair per session, Vault signs it (5-minute cert,
`boundary-client` role), and the certificate is **injected** — it never reaches
the operator's machine (Plus tier).

What's here:

- `hcp_boundary_cluster` (Plus) with initial password-auth admin — OIDC to an
  IdP is the documented follow-up
- Scopes `hashi-platform` (org) → `platform` (project)
- Egress worker: controller-led registration, tags `type = ["egress","vault"]`
- **Dynamic AWS host catalog** discovering instances tagged `boundary-target=ssh`
  (dedicated IAM user, `ec2:DescribeInstances` only — the one documented static
  credential; rotation disabled because Terraform manages the key)
- **Vault credential store** with `worker_filter` routing Vault API calls through
  the egress worker (Vault has no public endpoint), holding a 24h-periodic orphan
  token with exactly the two Layer-3 policies
- Var-gated **demo target** (`enable_demo_target=false` destroys it) that trusts
  the Vault SSH CA via user_data

## Run

Order matters the first time:

1. `0-bootstrap` re-applied locally (agent pool, new workspace, execution modes)
2. `1-tfc-agent` applied, agent shows **Idle** in org Settings → Agents
3. `3-vault-config` applied (SSH CA + policies)
4. In workspace `7-boundary`, set the **sensitive** Terraform variable
   `boundary_admin_password` (≥ 8 chars) once in the UI
5. PR → merge → confirm apply (cluster creation takes ~10 minutes)

## Definition of Done — the zero-keys login

From your laptop (only the `boundary` CLI installed, no keys anywhere):

```sh
export BOUNDARY_ADDR=$(terraform output ... or the boundary_cluster_url output)
boundary authenticate password -login-name admin
boundary targets list -recursive            # find private-ssh target id
boundary connect ssh -target-id <ttcp_...>  # lands on the demo target as ec2-user
```

`sudo journalctl -u sshd` on the target shows certificate auth; your laptop
holds no key material at any point. Removing the instance's
`boundary-target=ssh` tag makes it vanish from the catalog — access follows
infrastructure, not inventory files.

## Notes

- Replacing the worker instance requires tainting `boundary_worker.egress`
  too (activation tokens are single-use).
- Avoid running `3-vault-config` and `7-boundary` applies concurrently — each
  mints its own short-lived Vault admin token.
- OIDC auth method (Auth0/Entra) and session recording are the documented
  next hardening steps on this layer.
