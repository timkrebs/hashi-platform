# hashi-platform infrastructure

Terraform for the hashi-platform EKS environments. State and runs live in HCP
Terraform (organization `tim-krebs-org`, project `hashi-platform`). Workspaces
use remote execution, so plans and applies run inside HCP Terraform whether
they are started from a laptop or from GitHub Actions.

## Layout

```text
infra/
├── modules/
│   ├── aws-vpc/                       # EKS-ready VPC: subnets per AZ, NAT, LB subnet tags
│   ├── aws-eks-cluster/               # EKS control plane, managed node groups, EBS CSI IRSA
│   ├── aws-load-balancer-controller/  # NLB/ALB controller with IRSA (platform layer)
│   ├── cert-manager/                  # certificates for in-cluster TLS (platform layer)
│   ├── argocd/                        # Argo CD plus the in-cluster secret bridge (platform layer)
│   ├── argocd-root-app/               # root Application syncing gitops/clusters/<env>
│   ├── vault-aws-prerequisites/       # KMS unseal key, IRSA roles, init secret for Vault
│   └── boundary/                      # HCP Boundary placeholder, disabled
├── policies/                          # Sentinel policy set evaluated by HCP Terraform
└── environments/
    ├── dev/
    │   ├── cluster/                   # layer 1: network + EKS,   workspace hashi-platform-dev
    │   └── platform/                  # layer 2: add-ons + Argo,  workspace hashi-platform-dev-platform
    ├── staging/                       # same two layers, workspaces hashi-platform-staging[-platform]
    └── production/                    # same two layers, workspaces hashi-platform-production[-platform]
```

## Layers

Each environment has two root modules, applied in this order:

1. **`cluster/`** builds the network and the EKS cluster from `aws-vpc` and
   `aws-eks-cluster`. Its outputs (API endpoint, CA, OIDC provider, VPC id,
   account id) reach the next layer through HCP Terraform remote state.
2. **`platform/`** prepares the cluster for GitOps: the AWS Load Balancer
   Controller, cert-manager, Vault's AWS prerequisites (KMS unseal key, IRSA
   roles, Secrets Manager secret for the init output), Argo CD, and the root
   Argo CD Application that syncs `gitops/clusters/<env>` from the
   environment's branch. Workloads such as Vault are reconciled by Argo CD
   from there, not by Terraform.

```hcl
# environments/<env>/platform/main.tf (excerpt)
module "argocd_root_app" {
  source          = "../../../modules/argocd-root-app"
  repo_url        = "https://github.com/timkrebs/hashi-platform.git"
  target_revision = "dev"
  path            = "gitops/clusters/dev"

  depends_on = [module.argocd, module.aws_load_balancer_controller, module.cert_manager]
}
```

Why two layers: the `kubernetes` and `helm` providers need a reachable
cluster at plan time. Keeping them out of the state that creates the cluster
avoids provider configuration that depends on resources in the same plan,
which breaks on cluster replacement and on destroy. The platform layer
authenticates with a token from `aws_eks_cluster_auth`, so no `aws` CLI is
needed on HCP Terraform workers.

Destroy order is platform first, then cluster. The root Application carries
the Argo CD resources finalizer and its Helm release waits on uninstall, so
Terraform does not remove the load balancer controller until Argo CD has
deleted the workloads and the AWS objects they created (NLBs, EBS volumes).

Terraform hands account-specific values to GitOps through annotations on the
Argo CD in-cluster secret (`hashi-platform.io/*`: account id, region, KMS
alias, IRSA role ARNs, init secret name, Vault allow-list). ApplicationSets
read them with a cluster generator, so nothing under `gitops/` has to know
the account. The repository is public; keep it that way by never putting
identifiers or secrets in `gitops/`.

The network and the cluster remain separate modules because they have
different lifecycles. Dependencies flow through the root modules only;
modules never reference each other directly.

## Branches, environments and workspaces

| Branch | Roots under `infra/environments/<env>/` | HCP Terraform workspaces (cluster, platform) | GitHub environment |
| --- | --- | --- | --- |
| `dev` | `cluster/`, `platform/` | `hashi-platform-dev`, `hashi-platform-dev-platform` | `dev` |
| `staging` | `cluster/`, `platform/` | `hashi-platform-staging`, `hashi-platform-staging-platform` | `staging` |
| `production` | `cluster/`, `platform/` | `hashi-platform-production`, `hashi-platform-production-platform` | `production` |

Changes flow dev → staging → production by pull request between the branches.
Each root module names its workspace in `terraform.tf`, so the branch alone
decides where a run lands. `dev` and `staging` are ephemeral and are torn
down when they are promoted or left idle; see
[Ephemeral environments](#ephemeral-environments).

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
cd infra/environments/dev/cluster
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars

cd ../platform            # once the cluster layer has been applied
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

The platform layer reads the cluster layer's outputs through remote state, so
its plans only succeed once the cluster workspace has state and shares it
(see one-time setup). Its `kubernetes`/`helm` providers reach the API through
the public endpoint the cluster exposes.

Environment identity (project, environment name, cluster name, common tags)
is fixed in each layer's `locals.tf`. Tunables such as the region, VPC CIDR,
node groups and the Vault allow-list are variables with sensible defaults,
overridden in `<environment>.tfvars`. Those files are committed on purpose
because CI plans with them; never put secrets in them. The root `.gitignore`
still lists the exceptions at the old `infra/environments/<env>/<env>.tfvars`
paths; the layered files were added with `git add -f` and stay tracked, but
the exceptions should be moved to `!infra/environments/<env>/*/<env>.tfvars`.

After the first apply, `terraform output configure_kubectl` prints the command
that writes a kubeconfig entry.

## CI/CD

> **Layer migration pending.** The workflows, the Makefile and the root
> `.gitignore` were written for one root per environment at
> `infra/environments/<env>`. They have not been updated for the `cluster/`
> and `platform/` layout yet, so until that happens CI finds no `main.tf` at
> the old path and skips plan, apply and destroy. The required changes are
> listed under [Required changes outside infra/](#required-changes-outside-infra).

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

**`terraform-destroy.yml`** runs when a promotion pull request is merged
(`dev → staging` destroys dev, `staging → production` destroys staging) and
on manual dispatch for dev or staging. It checks out the environment's own
branch and runs `terraform destroy` as a remote run, bound to that
environment's GitHub environment and sharing the apply workflow's concurrency
group. Production is never a target. Details under
[Ephemeral environments](#ephemeral-environments).

One-time setup:

- **HCP Terraform**: two workspaces per environment in the `hashi-platform`
  project, execution mode *remote*, Terraform version `~> 1.15.0`, auto-apply
  off: `hashi-platform-<name>` with **working directory
  `infra/environments/<name>/cluster`** and `hashi-platform-<name>-platform`
  with **working directory `infra/environments/<name>/platform`**. The working
  directory matters: without it the CLI uploads only the root folder and
  remote runs fail with "Unreadable module directory" because
  `../../../modules` is missing. With it, the CLI uploads the whole repository
  and runs in the subdirectory. On the cluster workspace enable **remote state
  sharing** with its platform workspace. On dev and staging set
  `auto-destroy-activity-duration` to `1d` on the platform workspace and `2d`
  on the cluster workspace, so the platform layer is always torn down first.
  Create a team (for example `ci`) with *plan* and *apply* on all workspaces
  and generate a team token for it.
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

### Required changes outside infra/

The layered layout is complete inside `infra/`; these pieces elsewhere still
have to follow before it deploys through CI:

- `.github/workflows/terraform-plan.yml`, `terraform-apply.yml`,
  `terraform-destroy.yml`: resolve `infra/environments/<env>/<layer>` per
  layer; apply `cluster` (saved plan, environment approval) and then
  `platform` (fresh plan and apply in the same approved job, because the
  Kubernetes token in a saved plan expires after 15 minutes); destroy in
  reverse order and stop on the first failure; skip the platform layer while
  the cluster workspace has no state (HCP API `resource-count`); post one
  plan comment per layer.
- `Makefile`: `ENV_DIRS` glob `infra/environments/*/*/main.tf`, a `LAYER`
  variable for `make plan`.
- `.gitignore`: tfvars exceptions `!infra/environments/<env>/*/<env>.tfvars`.
- `.github/dependabot.yml`: Terraform directories `/infra/environments/*/*`.
- HCP Terraform: working directories, platform workspaces, remote state
  sharing and auto-destroy durations as listed under one-time setup.
- The `gitops/` tree Argo CD syncs (`gitops/clusters/<env>`, the Vault
  application and its values) does not exist yet; the root Application will
  report a missing path until it lands.

## Ephemeral environments

`dev` and `staging` exist only while something is being tested there;
`production` is permanent. Two mechanisms keep the short-lived ones from
running up a bill:

- **Destroyed on promotion.** Merging `dev → staging` destroys dev, merging
  `staging → production` destroys staging. The `terraform-destroy.yml`
  workflow reacts to the merged pull request, checks out the environment's own
  branch and runs `terraform destroy` as a remote run in HCP Terraform. It is
  bound to the environment's GitHub environment, so staging's required
  reviewers gate its teardown, and it shares the apply workflow's concurrency
  group, so a push that lands during the destroy queues and recreates the
  environment afterwards. The destroy and the promoted environment's apply run
  in parallel; they touch different workspaces.
- **Destroyed after a day without runs.** The dev and staging workspaces have
  `auto-destroy-activity-duration = 1d`. HCP Terraform queues a destroy run
  itself once a workspace has been idle for a day, which covers abandoned
  branches and failed destroy workflows. Raise it in the workspace settings if
  a test has to survive a weekend.
- **Manual teardown.** Run the *Terraform destroy* workflow by hand, pick the
  environment and type its name again to confirm. Production is not offered.
- **Recreation.** The next push to the branch, or a manual run of *Terraform
  apply*, rebuilds the environment from scratch. Expect 15 to 20 minutes each
  way for an EKS cluster.

Rules that keep destroys clean:

- AWS resources created from inside the cluster (NLBs from `LoadBalancer`
  services, EBS volumes from persistent volume claims) are only allowed for
  workloads Argo CD manages through the root Application, because deleting
  that Application cascades to them before Terraform uninstalls the load
  balancer controller and the cluster. Workloads must clean up after
  themselves: `LoadBalancer` services are deleted with the app, and
  StatefulSets in ephemeral environments set
  `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete`. Anything created
  by hand with `kubectl` is invisible to both Terraform and Argo CD and blocks
  the VPC destroy; CI has no AWS credentials to clean it up.
- Destroy the platform layer before the cluster layer, never the other way
  round. If the cluster goes first, the controller that deletes NLBs is gone
  and the VPC destroy fails.
- If a destroy run fails, fix the cause in AWS (usually a leftover load
  balancer or network interface), then rerun the workflow by hand.
- Remote runs use the credentials in the `AWS_ACCOUNT_CREDENTIALS` variable
  set. An expired session makes the destroy fail and the environment keeps
  billing until someone notices.
- A saved plan left in the workspace from before the destroy refers to
  infrastructure that no longer exists; discard it in HCP Terraform.
- Dev schedules its cluster KMS key for deletion after the minimum 7 days
  (`kms_key_deletion_window_in_days` on the cluster module) so rebuilt
  clusters do not accumulate keys pending deletion.

## Policies

HCP Terraform evaluates the Sentinel policy set in [`policies/`](policies/)
after every plan in the `hashi-platform` project. Two hard-mandatory policies
apply today: every taggable AWS resource must carry `Environment`, `Project`
and `ManagedBy`, and no instance type may be larger than `medium`. The policy
set is VCS-backed with policies path `infra/policies`; policy changes take
effect once they land on the branch the set follows. See the
[policies README](policies/README.md) for details and local testing.

## Adding an environment

1. Create both HCP Terraform workspaces (`hashi-platform-<name>` with working
   directory `infra/environments/<name>/cluster`, `hashi-platform-<name>-platform`
   with `infra/environments/<name>/platform`), enable remote state sharing
   from the first to the second, and create the GitHub environment.
2. Copy `environments/dev` (both layers) to `environments/<name>`.
3. In each layer's `terraform.tf`, point the `cloud` block at the new
   workspace; in `platform/data.tf`, point the remote state at the new
   cluster workspace.
4. In each layer's `locals.tf`, set `environment`.
5. Rename `dev.tfvars` to `<name>.tfvars` in both layers, choose a VPC CIDR
   that does not overlap with other environments (dev `10.0.0.0/16`, staging
   `10.1.0.0/16`, production `10.2.0.0/16`), size the node groups and set the
   Vault allow-list. For production, also set `single_nat_gateway = false` on
   the network module and keep the 30-day KMS and secret windows.
6. Add `!infra/environments/<name>/*/<name>.tfvars` to the root `.gitignore`,
   next to the existing exceptions.
7. Add `gitops/clusters/<name>/` and the environment's values files under
   `gitops/apps/*/values/` once the GitOps tree exists.
8. Add the branch name to the `branches` lists in `terraform-plan.yml` and
   `terraform-apply.yml`.
9. If the environment is ephemeral, set `auto-destroy-activity-duration`
   (`1d` platform, `2d` cluster), pass `kms_key_deletion_window_in_days = 7`
   to the cluster module, use the 7-day KMS and 0-day secret windows in the
   platform tfvars, and add its promotion pair and dispatch option to
   `terraform-destroy.yml`.

## Testing the modules

Every module ships unit tests that run in plan mode against mocked providers
(`aws`, `helm`, `kubernetes`, `hcp` as needed), so they need no cloud
credentials or cluster access, only registry access for providers and
upstream modules:

```sh
for module in infra/modules/*/; do
  terraform -chdir="$module" init -backend=false && terraform -chdir="$module" test
done
```

Before committing, run from the repository root:

```sh
terraform fmt -recursive infra
tflint --init --config "$PWD/.tflint.hcl"
tflint --recursive --config "$PWD/.tflint.hcl"
```

## Upstream module versions

| Dependency                                                        | Version |
|-------------------------------------------------------------------|---------|
| terraform-aws-modules/vpc/aws                                     | 5.8.1   |
| terraform-aws-modules/eks/aws                                     | 20.8.5  |
| terraform-aws-modules/iam/aws (assumable-role-oidc, irsa-eks)     | 5.39.0  |
| Helm chart eks/aws-load-balancer-controller                       | 3.5.0   |
| Helm chart jetstack/cert-manager                                  | 1.21.1  |
| Helm chart argo/argo-cd                                           | 10.7.1  |
| Helm chart argo/argocd-apps                                       | 2.0.5   |

These are pinned inside the modules. Bump them there and run the unit tests
plus a plan in dev before rolling forward. Dependabot does not track Helm
charts; bump them by hand.
