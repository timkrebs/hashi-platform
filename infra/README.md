# hashi-platform infrastructure

Terraform for the hashi-platform EKS environments. State and runs live in HCP
Terraform (organization `tim-krebs-org`, project `hashi-platform`). Workspaces
use remote execution, so plans and applies run inside HCP Terraform whether
they are started from a laptop or from GitHub Actions.

## Layout

```text
infra/
├── modules/
│   ├── aws-vpc/           # EKS-ready VPC: subnets per AZ, NAT, LB subnet tags
│   └── aws-eks-cluster/   # EKS control plane, managed node groups, EBS CSI IRSA
├── policies/              # Sentinel policy set evaluated by HCP Terraform
└── environments/
    ├── dev/               # root module, workspace hashi-platform-dev
    ├── staging/           # root module, workspace hashi-platform-staging
    └── production/        # root module, workspace hashi-platform-production
```

Each environment is its own root module that composes the two modules:

```hcl
module "network" {
  source = "../../modules/aws-vpc"
  # ...
}

module "eks" {
  source     = "../../modules/aws-eks-cluster"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids
  # ...
}
```

The network and the cluster are separate modules because they have different
lifecycles: a VPC is typically shared and outlives any single cluster, and a
cluster can be rebuilt without touching the network. Dependencies flow through
the root module only; modules never reference each other directly.

## Branches, environments and workspaces

| Branch       | Root module                          | HCP Terraform workspace      | GitHub environment |
|--------------|--------------------------------------|------------------------------|--------------------|
| `dev`        | `infra/environments/dev`             | `hashi-platform-dev`         | `dev`              |
| `staging`    | `infra/environments/staging`         | `hashi-platform-staging`     | `staging`          |
| `production` | `infra/environments/production`      | `hashi-platform-production`  | `production`       |

Changes flow dev → staging → production by pull request between the branches.
Each root module names its workspace in `terraform.tf`, so the branch alone
decides where a run lands.

## Prerequisites

- Terraform `~> 1.15.0` (the environments pin this; modules accept `>= 1.9`)
- `terraform login` for HCP Terraform
- Optional: [tflint](https://github.com/terraform-linters/tflint)

AWS credentials are not needed locally: remote runs read them from the
`AWS_ACCOUNT_CREDENTIALS` variable set in HCP Terraform. That set currently
holds short-lived session credentials, so runs fail once they expire until
the set is refreshed. HCP Terraform dynamic provider credentials (OIDC from
`app.terraform.io` to an IAM role) would remove that chore if the account
allows the provider.

## Working on an environment

```sh
cd infra/environments/dev
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

Environment identity (project, environment name, cluster name, common tags)
is fixed in `locals.tf`. Tunables such as the region, VPC CIDR and node groups
are variables with sensible defaults, overridden in `<environment>.tfvars`.
That file is committed on purpose (the root `.gitignore` lists it as an
exception to the general `*.tfvars` rule) because CI plans with it; never
put secrets in it.

After the first apply, `terraform output configure_kubectl` prints the command
that writes a kubeconfig entry.

## CI/CD

Two workflows in `.github/workflows` drive the pipeline. Both derive the
environment from the branch and skip plan and apply until the environment's
`main.tf` exists.

**`terraform-plan.yml`** runs on pull requests into `dev`, `staging` or
`production`:

1. `terraform fmt -check`, `tflint --recursive` (config in the repo root),
   `terraform validate` and `terraform test` for both modules, and
   `terraform validate` for the target environment root.
2. A speculative plan in HCP Terraform for the target environment. The result
   is posted as a comment on the pull request (one comment per environment,
   updated on every push) and in the job summary, with a link to the HCP run.

**`terraform-apply.yml`** runs on pushes to those branches (so, on merge) and
on manual dispatch:

1. `terraform plan -out=tfplan`, which creates an applyable run in HCP
   Terraform. The job ends here when the plan has no changes.
2. `terraform apply tfplan` in a job bound to the GitHub environment of the
   same name, so required reviewers and wait timers configured there gate
   the apply. Exactly the saved plan is applied, not a fresh one.

One-time setup:

- **HCP Terraform**: one workspace per environment in the `hashi-platform`
  project, execution mode *remote*, Terraform version `~> 1.15.0`, auto-apply
  off, and **working directory `infra/environments/<name>`**. The working
  directory matters: without it the CLI uploads only the environment folder
  and remote runs fail with "Unreadable module directory" because
  `../../modules` is missing. With it, the CLI uploads the whole repository
  and runs in the subdirectory. Create a team (for example `ci`) with *plan*
  and *apply* on those workspaces and generate a team token for it.
- **GitHub secret** `TF_API_TOKEN` (repository level) holding that team token.
  The pull request plan job runs outside any GitHub environment, so the token
  must be available at repository level. For tighter control, add
  environment-level `TF_API_TOKEN` secrets with per-environment team tokens;
  the apply job picks those up automatically.
- **GitHub environments** `dev`, `staging`, `production`. Add required
  reviewers to `staging` and `production`, and restrict each environment to
  its branch.
- **Branch protection** on the three branches: require a pull request and
  the `Static checks` and `Plan <environment>` status checks.

If a reviewer rejects an apply, the HCP Terraform run stays in
*planned and saved*; discard it from the HCP Terraform UI so it does not
linger in the workspace's run list.

## Policies

HCP Terraform evaluates the Sentinel policy set in [`policies/`](policies/)
after every plan in the `hashi-platform` project. Two hard-mandatory policies
apply today: every taggable AWS resource must carry `Environment`, `Project`
and `ManagedBy`, and no instance type may be larger than `medium`. The policy
set is VCS-backed with policies path `infra/policies`; policy changes take
effect once they land on the branch the set follows. See the
[policies README](policies/README.md) for details and local testing.

## Adding an environment

1. Create the HCP Terraform workspace with working directory
   `infra/environments/<name>` (see one-time setup) and the GitHub
   environment.
2. Copy `environments/dev` to `environments/<name>`.
3. In `terraform.tf`, point the `cloud` block at the new workspace.
4. In `locals.tf`, set `environment`.
5. Rename `dev.tfvars` to `<name>.tfvars`, choose a VPC CIDR that does not
   overlap with other environments, and size the node groups. For
   production, also set `single_nat_gateway = false` on the network module
   in `main.tf`.
6. Add `!infra/environments/<name>/<name>.tfvars` to the root `.gitignore`,
   next to the existing exceptions.
7. Add the branch name to the `branches` lists in both workflows.

## Testing the modules

Both modules ship unit tests that run in plan mode against mocked providers,
so they need no AWS credentials or network access beyond the registry:

```sh
cd infra/modules/aws-vpc         && terraform init -backend=false && terraform test
cd infra/modules/aws-eks-cluster && terraform init -backend=false && terraform test
```

Before committing, run from the repository root:

```sh
terraform fmt -recursive infra
tflint --init --config "$PWD/.tflint.hcl"
tflint --recursive --config "$PWD/.tflint.hcl"
```

## Upstream module versions

| Module                                             | Version |
|----------------------------------------------------|---------|
| terraform-aws-modules/vpc/aws                      | 5.8.1   |
| terraform-aws-modules/eks/aws                      | 20.8.5  |
| terraform-aws-modules/iam/aws (assumable-role-oidc)| 5.39.0  |

These are pinned inside the modules. Bump them there and run the unit tests
plus a plan in dev before rolling forward.
