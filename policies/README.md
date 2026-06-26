# Sentinel policies

Policy-as-code guardrails enforced by HCP Terraform during the plan phase of
every run, before apply. Each policy derives the target environment from the
workspace name (`hashi-platform-<env>`), so one policy set governs all three
workspaces.

## Policies

| Policy | Enforcement | What it does |
| --- | --- | --- |
| `restrict-node-instance-types` | soft-mandatory | Limits EKS node-group instance types to an approved list per environment. |
| `limit-node-group-size` | soft-mandatory | Caps `max_size` of each node group per environment. |
| `require-environment-tags` | advisory | Flags resources missing `Project`, `Environment`, or `ManagedBy` tags. |
| `enforce-cost-by-environment` | advisory | Warns when the estimated monthly cost exceeds the environment ceiling. |

### Per-environment limits

| Environment | Instance types | Max node size | Cost ceiling |
| --- | --- | --- | --- |
| dev | `t3.micro/small/medium` | 3 | $300/mo |
| staging | `t3.medium/large/xlarge`, `m5.large/xlarge` | 6 | $800/mo |
| prod | `m5.*`, `c5.*`, `r5.*` | 20 | $3000/mo |

## Enforcement levels

- **advisory** - logs a warning, never blocks.
- **soft-mandatory** - blocks the run, but an org/workspace admin can override.
- **hard-mandatory** - blocks the run, cannot be overridden.

## How node sizing works

`infra/aws-eks` exposes `node_instance_types` as a variable (default
`["t3.small"]`, valid for dev). Each workspace sets its own value as an HCP
Terraform **workspace variable**, and Sentinel validates that the value is
within the environment's allowed list. Set `node_instance_types` on the
`staging` and `prod` workspaces, or their runs will be denied (the default
`t3.small` is not in the staging/prod allow-list - that is the policy working).

## Wiring it into HCP Terraform

> Sentinel policy sets require the HCP Terraform **Plus** edition (or the legacy
> Team & Governance tier). On the free/standard tier you can still develop and
> test policies locally with the Sentinel CLI, but you cannot attach a policy
> set to a workspace.

1. In the org, go to **Settings -> Policy Sets -> Connect a new policy set**.
2. Choose **Sentinel**, connect this GitHub repository, and set the policies
   path to `policies`.
3. Scope the policy set to the `hashi-platform-dev`, `-staging`, and `-prod`
   workspaces (or to a project containing them).
4. The policy set tracks the connected branch; point it at `main` once these
   policies are promoted there.

## Local development

```bash
sentinel fmt policies/        # format
make sentinel                 # fmt check via the Makefile (skips if CLI absent)
```

Full `sentinel test` runs require mock data (`tfplan/v2`, `tfrun`) under a
`test/` directory; add mocks per policy to unit-test them in CI before they
ever reach a workspace.
