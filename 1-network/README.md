# Layer 1 — Network

The VPC and private connectivity everything else lands in:

- VPC `10.0.0.0/16`, 3 AZs: public subnets (NAT only) + private subnets (all compute)
- Internet gateway; NAT (`single` by default — set `nat_gateway_strategy = "per_az"`
  for the production posture; trade-off documented on the variable)
- **HVN `172.25.16.0/20` (permanent CIDR) + HVN ↔ VPC peering**, routed on both sides
- Role-based security groups (`consul-server`, `nomad-server`, `nomad-client`,
  `boundary-worker`) referencing each other by SG ID
- The critical JWKS rule: `nomad-server` allows `:4646` **from the HVN CIDR** so Vault
  can validate Nomad workload identities (Layer 5 depends on it)
- Per-role IAM instance roles/profiles with the cloud auto-join policy, plus the
  auto-join tag standard (`auto_join` output)

## Run

This layer runs **in HCP Terraform** (workspace `1-network`, created by `0-bootstrap`)
— never locally:

1. Branch, change, open a PR → GitHub Actions gate + HCP Terraform speculative plan.
2. Merge to `main` → the workspace queues a plan.
3. Review and **confirm the apply in the HCP Terraform UI** (no auto-apply).

There is no tfvars file: the defaults *are* the pinned design (CIDR plan from the
reference architecture). Override only via workspace variables, and never `hvn_cidr`
after creation.

## Definition of Done

1. Peering is `active` on both sides (HCP portal and AWS console agree).
2. A throwaway instance in a private subnet (no public IP) can reach the internet via
   NAT, e.g. `curl -sI https://checkpoint-api.hashicorp.com/v1/check/terraform`.
3. The same instance can route toward the HVN CIDR (full proof lands with Layer 2:
   `nc -zv <vault-private-ip> 8200`).

Delete the throwaway instance afterwards; nothing in this layer runs compute.

## Outputs

`vpc_id`, subnet/route-table maps by AZ, `security_group_ids`, `hvn_id`,
`aws_peering_connection_id`, instance profile names/ARNs, and the `auto_join` tag
standard — consumed by Layers 2, 4, 5, 6, 7 via `tfe_outputs`.
