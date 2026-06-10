# Layer 7a — Boundary cluster

Provisions the **HCP Boundary cluster** only. Split from [7-boundary](../7-boundary)
so the `boundary` provider in that layer authenticates against a cluster that
already exists.

## Why this is its own layer

The `boundary` provider needs `addr` (the cluster URL) and logs in at provider
configuration time. If the cluster is created in the *same* run, its URL is
unknown during plan and the provider falls back to its default
`http://127.0.0.1:9200`, producing `connection refused`. Creating the cluster
here and reading its URL via `tfe_outputs` in `7-boundary` removes that
same-run dependency — no `-target` workarounds.

What's here:

- `hcp_boundary_cluster` (Plus by default) with the initial password-auth admin

Outputs `cluster_url` and `cluster_uuid`, consumed by `7-boundary`.

## Run

1. Set the **sensitive** Terraform variable `boundary_admin_password` (≥ 8 chars)
   once in the `7-boundary-cluster` workspace UI. Keep it identical to the value
   in `7-boundary` (the provider logs in with the same credentials).
2. PR → merge → confirm apply (cluster creation takes ~10 minutes).
3. Then apply `7-boundary`.

Runs in **remote** execution mode — it only talks to the public HCP control
plane, so it does not need the in-VPC agent.
