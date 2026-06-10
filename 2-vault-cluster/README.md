# Layer 2 — Vault cluster (provision)

Provisions **HCP Vault Dedicated** inside the Layer-1 HVN. Provisioning only —
everything *inside* Vault (audit, auth methods, secrets engines, policies) is
Layer 3, a separate lifecycle with a smaller blast radius.

- Consumes `hvn_id` from the `1-network` workspace via `tfe_outputs` (the run's
  own token reads it; no extra credentials)
- `public_endpoint = false` — locked decision; the API exists only on the private
  endpoint over the HVN ↔ VPC peering on `:8200`
- `tier = "dev"` by default: single node, no HA, lowest cost. Set the `tier`
  workspace variable to `standard_small` when you want to demonstrate the HA story
- **No admin token lives here.** `hcp_vault_cluster_admin_token` is a 6-hour
  credential; Layer 3 creates its own at the start of each run rather than
  parking one in shared state

## Run

Depends on Layer 1 being applied (the `tfe_outputs` read fails otherwise).

1. PR → GitHub Actions gate + HCP Terraform speculative plan.
2. Merge to `main` → workspace `2-vault-cluster` queues a plan.
3. Review and confirm the apply in the HCP Terraform UI.

Cluster creation takes ~10–15 minutes.

## Definition of Done

From a throwaway instance in a private subnet (no public IP):

```sh
VAULT_HOST=$(echo "<vault_private_endpoint_url>" | sed -E 's#https?://##; s#:.*##')
nc -zv "$VAULT_HOST" 8200
curl -sk "<vault_private_endpoint_url>/v1/sys/health"
```

Both succeed across the peering; the HCP portal shows the cluster with the
private endpoint only. Delete the throwaway instance afterwards.

## Outputs

`vault_cluster_id`, `vault_private_endpoint_url`, `vault_namespace`.
