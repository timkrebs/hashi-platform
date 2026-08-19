# Sentinel Compliance Policies

Policy-as-code for the hashi-platform Terraform stacks. These policies run
**inside a Terraform run**: HCP Terraform executes them against the plan
after `terraform plan` succeeds and **before `terraform apply` is allowed
to start**.

```text
terraform plan  ──▶  Sentinel policy check  ──▶  terraform apply
                        │
                        ├─ advisory        → warn, continue
                        ├─ soft-mandatory  → block, override possible
                        └─ hard-mandatory  → block, no override
```

Each policy receives the plan through the `tfplan/v2` import and inspects
the `resource_changes` and `variables` — the same data you see in
`terraform show -json <planfile>`. A policy passes when its `main` rule
evaluates to `true`.

## Policies in this set

| Policy | Enforcement | What it checks | Repo status |
| --- | --- | --- | --- |
| `restrict-aws-regions` | hard-mandatory | `region` variable must be an approved region (eu-central-1, eu-north-1, us-east-1) | `eu-central-1` |
| `eks-approved-cluster-version` | hard-mandatory | `aws_eks_cluster` version must be on the approved list (1.32–1.34) | `1.34` |
| `vault-approved-secret-engines` | hard-mandatory | `vault_mount` types must be vetted (kv-v2, pki, transit) | `kv-v2`, `pki` |
| `restrict-instance-types` | soft-mandatory | `aws_eks_node_group` instance types must be on the approved list | `t3.medium` |
| `enforce-tagging-standard` | soft-mandatory | mandatory tags `prefix`/`env`/`region` + `Name` follows the naming convention | via `default_tags` |
| `eks-node-group-size-limits` | advisory | node groups scale between min 1 and max 5 nodes | max 3 / max 2 |

**The current code is compliant with every policy**, so the policy check
passes and the run proceeds to apply. The `fail` mocks in the test suite
show what a blocked run would look like.

## Naming and tagging convention

```text
{prefix}-{env}-{region}-{component}[-{qualifier}][-{az}]
   hp   - dev -  euc1  -    eks    -   ng-default
```

| Token | Values | Notes |
| --- | --- | --- |
| prefix | `hp` | fixed |
| env | `dev`, `stg`, `prd` | fixed 3 chars, aligns in console |
| region | `euc1`, `eun1`, `use1` | eu-central-1, eu-north-1, us-east-1 |
| az | `1a`, `1b`, `1c` | last chars of the AZ name |

Implementation in `terraform/10-cluster`:

- The AWS provider's `default_tags` stamps `prefix`, `env`, `region` on
  **every** taggable resource.
- Resource names are derived from `local.name_prefix`
  (`hp-dev-euc1-…`): VPC `hp-dev-euc1-vpc`, cluster `hp-dev-euc1-eks`,
  node groups `hp-dev-euc1-eks-ng-default` / `-ng-spare`, subnets with the
  az token, e.g. `hp-dev-euc1-snet-private-1a`.
- The `env` and `region` variables carry `validation` blocks, so invalid
  tokens already fail at `terraform plan` — Sentinel then enforces the
  same standard org-wide, for code that doesn't use these variables.

`enforce-tagging-standard` verifies both: the three mandatory tag keys
with approved values (checked against `tags_all`, which includes
`default_tags`), and — where a `Name` tag exists — that it matches
`^hp-(dev|stg|prd)-(euc1|eun1|use1)-[a-z0-9]+(-[a-z0-9]+)*$`.

## HCP Terraform policy set compatibility

Verified against the policy set requirements — this directory can be
connected as-is as a VCS-backed policy set:

- `sentinel.hcl` sits at the root of the policies path with one
  `policy` block per policy.
- Policy names exactly match their `.sentinel` filenames, sources use
  relative `./` paths in the same directory.
- Only valid enforcement levels are used (`advisory`,
  `soft-mandatory`, `hard-mandatory`).
- Only the standard `tfplan/v2` import is used — no custom modules or
  params that would need extra policy set configuration.
- The `test/` directory is ignored by HCP Terraform (only files
  referenced in `sentinel.hcl` are loaded), and all policies pass
  `sentinel test` on the same runtime HCP Terraform embeds.

## Run the policies locally

Tests live in `test/<policy-name>/` with a `pass.hcl` and `fail.hcl` case
each. The *pass* mocks mirror the repo's current configuration; the *fail*
mocks are hypothetical violations (region `ap-southeast-2`, cluster
version `1.21`, an `ssh` secret engine, an `m5.24xlarge` node, a node
group scaled to 20, an untagged `legacy-vpc`).

```shell
brew install hashicorp/tap/sentinel   # one-time
cd policies
sentinel test              # all policies, all cases
sentinel test -run enforce-tagging-standard -verbose   # see violation output
```

## Enforce in a real terraform apply run (HCP Terraform)

1. Connect the workspaces (`10-cluster`, `20-vault-config`) to HCP
   Terraform — uncomment the `cloud {}` block in
   [terraform.tf](../terraform/10-cluster/terraform.tf).
2. In the HCP Terraform UI: **Organization Settings → Policy Sets →
   Connect a policy set**, point it at this repository with
   `policies` as the policies path, and attach it to the workspaces
   (or all workspaces).
3. Run `terraform plan` / `terraform apply` from the CLI or via VCS as
   usual. The run output now shows a **Policy check** stage between plan
   and apply — with the current code, **all 6 policies pass** and the
   apply proceeds.
4. To demo enforcement, introduce a violation and watch the run react:
   - set `region = "eu-west-3"` → *hard-mandatory* failure, the run
     errors and **apply never executes**, no override offered.
   - remove the `default_tags` block or rename a node group to
     `web-nodes` → *soft-mandatory* failure of `enforce-tagging-standard`,
     users with "Manage Policy Overrides" permission get an
     **Override & Continue** button (audited).
   - raise a node group to `max_size = 20` → *advisory* warning, the run
     continues to apply.

Policy sets can also be managed as code with the
[`tfe_policy_set`](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs/resources/policy_set)
resource instead of the UI.

## Layout

```text
policies/
├── sentinel.hcl                        # policy set: sources + enforcement levels
├── <policy-name>.sentinel              # one policy per rule
└── test/<policy-name>/
    ├── pass.hcl / fail.hcl             # expected outcome per mock
    └── mock-tfplan-{pass,fail}.sentinel  # hand-written tfplan/v2 mocks
```

Note: this directory is Sentinel policy-as-code for Terraform runs; the
`terraform/20-vault-config/policies/` directory holds **Vault ACL**
policies — same word, different plane.
