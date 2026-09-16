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
│   └── boundary/                      # HCP Boundary placeholder, disabled
├── policies/                          # Sentinel policy set evaluated by HCP Terraform
└── environments/
    └── dev/                           # the only environment
        ├── cluster/                   # layer 1: network + EKS,   workspace hashi-platform-dev
        └── platform/                  # layer 2: cluster add-ons, workspace hashi-platform-dev-platform
```

## Layers

There is one environment, `dev`, with two root modules applied in this order:

1. **`cluster/`** builds the network and the EKS cluster from `aws-vpc` and
   `aws-eks-cluster`. Its outputs (API endpoint, CA, OIDC provider, VPC id,
   account id) reach the next layer through HCP Terraform remote state.
2. **`platform/`** installs the in-cluster add-ons workloads depend on: the
   AWS Load Balancer Controller (with IRSA) and cert-manager. Secrets are
   served by HCP Vault Dedicated, which runs outside this configuration and is
   not managed by Terraform here.

```hcl
# environments/<env>/platform/main.tf (excerpt)
module "aws_load_balancer_controller" {
  source = "../../../modules/aws-load-balancer-controller"

  cluster_name      = local.cluster_name
  region            = var.region
  vpc_id            = local.cluster.vpc_id
  oidc_provider_arn = local.cluster.oidc_provider_arn

  tags = local.common_tags
}
```

Why two layers: the `kubernetes` and `helm` providers need a reachable
cluster at plan time. Keeping them out of the state that creates the cluster
avoids provider configuration that depends on resources in the same plan,
which breaks on cluster replacement and on destroy. The platform layer
authenticates with a token from `aws_eks_cluster_auth`, so no `aws` CLI is
needed on HCP Terraform workers.

Destroy order is platform first, then cluster, so the load balancer
controller is still running when the AWS objects that in-cluster workloads
created (NLBs, EBS volumes) have to go. Workloads deployed by hand must be
removed before the platform layer is destroyed; see
[Ephemeral environments](#ephemeral-environments).

The network and the cluster remain separate modules because they have
different lifecycles. Dependencies flow through the root modules only;
modules never reference each other directly.

## Branch, environment and workspaces

| Branch | Roots under `infra/environments/dev/` | HCP Terraform workspaces (cluster, platform) | GitHub environment |
| --- | --- | --- | --- |
| `main` | `cluster/`, `platform/` | `hashi-platform-dev`, `hashi-platform-dev-platform` | `dev` |

`main` is the only long-lived branch. Feature branches merge into it by pull
request; the merge applies. Each root module names its workspace in
`terraform.tf`. The environment is ephemeral and is torn down when it is left
idle; see [Ephemeral environments](#ephemeral-environments).

## Prerequisites

- Terraform `~> 1.15.0` (the environments pin this; modules accept `>= 1.9`).
  The exact version lives in `.terraform-version` at the repository root, so
  [tenv](https://github.com/tofuutils/tenv) selects it automatically; a 1.16
  binary fails `terraform init` on the environment roots.
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
node groups and the cert-manager toggle are variables with sensible defaults,
overridden in `<environment>.tfvars`. Those files are committed on purpose
because CI plans with them (the root `.gitignore` lists them as exceptions to
the general `*.tfvars` rule); never put secrets in them.

After the first apply, `terraform output configure_kubectl` prints the command
that writes a kubeconfig entry.

## CI/CD

Three workflows in `.github/workflows` drive the pipeline. They target the
single `dev` environment and derive the layers from which
`infra/environments/dev/<layer>/main.tf` files exist; a missing layer is
skipped with a notice. Whether the platform layer can run is decided by
asking HCP Terraform (through the composite action
`.github/actions/hcp-workspace-state`) whether the cluster workspace holds
resources.

**`terraform-plan.yml`** runs on pull requests into `main`:

1. `terraform fmt -check`, `tflint`, `terraform validate` and
   `terraform test` for every module, and `terraform validate` for each
   layer; Sentinel policy tests.
2. A speculative plan in HCP Terraform per layer. The platform layer is only
   planned once the cluster workspace holds resources. Each layer's result is
   posted as its own comment on the pull request (updated on every push) and
   in the job summary, with a link to the HCP run.

**`terraform-apply.yml`** runs on pushes to `main` (so, on merge) and on
manual dispatch:

1. `terraform plan -out=tfplan` for the cluster layer, which creates an
   applyable run in HCP Terraform.
2. One job bound to the `dev` GitHub environment, so required
   reviewers and wait timers configured there gate everything below: it
   applies exactly the saved cluster plan (skipped when that plan had no
   changes), then plans and applies the platform layer back to back. The
   platform layer never uses a saved plan because its Kubernetes token is
   only valid for about 15 minutes and would expire while a reviewer waits.
   The job runs whenever the cluster plan has changes or a platform layer
   exists, so platform-only changes still deploy.

**`terraform-destroy.yml`** runs on manual dispatch only; type `dev` in the
confirmation field to arm it. It destroys the platform layer first, then the
cluster layer, as remote runs bound to the `dev` GitHub environment and
sharing the apply workflow's concurrency group. If the platform destroy fails
the job stops and the cluster stays; if the cluster workspace holds no
resources the platform destroy is skipped with a warning. The dispatch form
offers `layer = platform` to rehearse a platform teardown alone. Details under
[Ephemeral environments](#ephemeral-environments).

One-time setup:

- **HCP Terraform**: two workspaces in the `hashi-platform` project,
  execution mode *remote*, Terraform version `~> 1.15.0`, auto-apply off:
  `hashi-platform-dev` with **working directory
  `infra/environments/dev/cluster`** and `hashi-platform-dev-platform`
  with **working directory `infra/environments/dev/platform`**. The working
  directory matters: without it the CLI uploads only the root folder and
  remote runs fail with "Unreadable module directory" because
  `../../../modules` is missing. With it, the CLI uploads the whole repository
  and runs in the subdirectory. On the cluster workspace enable **remote state
  sharing** with its platform workspace. Set
  `auto-destroy-activity-duration` to `1d` on the platform workspace and `2d`
  on the cluster workspace, so the platform layer is always torn down first.
  Create a team (for example `ci`) with *plan* and *apply* on both workspaces
  and generate a team token for it.
- **GitHub secret** `TF_API_TOKEN` (repository level) holding that team token.
  The pull request plan job runs outside any GitHub environment, so the token
  must be available at repository level. For tighter control, add an
  environment-level `TF_API_TOKEN` secret on `dev`; the apply job picks it up
  automatically.
- **GitHub environment** `dev`. Add required reviewers there if applies should
  wait for approval, and restrict the environment to `main`.
- **Branch protection** on `main`: require a pull request and the
  `Static checks` and `Plan dev` status checks.

If a reviewer rejects an apply, the HCP Terraform run stays in
*planned and saved*; discard it from the HCP Terraform UI so it does not
linger in the workspace's run list.

## Ephemeral environment

`dev` exists only while something is being tested there. Two mechanisms keep
it from running up a bill:

- **Destroyed after a day without runs.** The dev workspaces have
  `auto-destroy-activity-duration` (`1d` platform, `2d` cluster). HCP
  Terraform queues a destroy run itself once a workspace has been idle,
  which covers forgotten environments and failed destroy workflows. Raise it
  in the workspace settings if a test has to survive a weekend.
- **Manual teardown.** Run the *Terraform destroy* workflow by hand and type
  `dev` to confirm.
- **Recreation.** The next push to `main`, or a manual run of *Terraform
  apply*, rebuilds the environment from scratch. Expect 15 to 20 minutes each
  way for an EKS cluster.

Rules that keep destroys clean:

- AWS resources created from inside the cluster (NLBs from `LoadBalancer`
  services, EBS volumes from persistent volume claims) must be gone before the
  platform layer is destroyed, because Terraform uninstalls the load balancer
  controller with it. Workloads must clean up after themselves:
  `LoadBalancer` services are deleted with the app, and StatefulSets set
  `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete`. Anything created
  by hand with `kubectl` is invisible to Terraform and blocks the VPC destroy;
  CI has no AWS credentials to clean it up.
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
- The cluster KMS key is scheduled for deletion after the minimum 7 days
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

The repository deliberately runs a single environment. To add a second one:

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
   that does not overlap with dev (`10.0.0.0/16`) and size the node groups.
6. Add `!infra/environments/<name>/*/<name>.tfvars` to the root `.gitignore`,
   next to the existing exception.
7. Parameterise the `ENVIRONMENT` variable in `terraform-plan.yml`,
   `terraform-apply.yml` and `terraform-destroy.yml`, which currently hard-code
   `dev`, and decide how a run picks between the environments.

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

These are pinned inside the modules. Bump them there and run the unit tests
plus a plan in dev before rolling forward. Dependabot does not track Helm
charts; bump them by hand.
