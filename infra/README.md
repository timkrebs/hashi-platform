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
│   ├── aws-checkmk-server/            # Checkmk Raw monitoring server on EC2 (platform layer)
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
2. **`platform/`** installs the in-cluster add-ons workloads depend on — the
   AWS Load Balancer Controller (with IRSA) and cert-manager — plus the Checkmk
   monitoring server on EC2. Secrets are served by HCP Vault Dedicated, which
   runs outside this configuration and is not managed by Terraform here.

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

### Hardened node images

Both EC2 estates run on the company's hardened images from the ami-prod account
(`888995627335`) for compliance: the Checkmk server on
`hc-base-ubuntu-2404-amd64-*`, and the EKS node groups on
`hc-base-ubuntu-2404-eks-<version>-amd64-*`.

Because those nodes are Ubuntu, kubelet is pointed away from the
systemd-resolved stub resolver; without that CoreDNS forwards to itself and
cluster DNS collapses. See the
[module README](modules/aws-eks-cluster/README.md#hardened-node-images).

The EKS image family is published per Kubernetes version, and the module derives
the name from `cluster_version`, so the node image can never drift ahead of the
control plane. Today only **1.35** has an image; there is none for 1.33 or 1.34.
Since EKS upgrades one minor version per apply, moving a live cluster onto the
hardened image is a sequence, not a single change:

| Step | `cluster_version` | `use_hardened_node_ami` | What happens |
| --- | --- | --- | --- |
| 1 | `1.34` | `false` | Control plane 1.33 -> 1.34, nodes stay on AL2023. |
| 2 | `1.35` | `false` | Control plane 1.34 -> 1.35, nodes still AL2023. |
| 3 | `1.35` | `true` | Node groups roll onto the hardened image. |

Each step is its own merge to `main`, and each rotates every node. Do not skip a
step: EKS rejects a two-minor jump, and turning the flag on at a version with no
published image fails the plan on the AMI lookup — by design, rather than
producing nodes that never join the cluster.

Kubernetes 1.33 is on extended support, which bills the control plane at roughly
six times the standard rate, so this sequence also takes the cluster off that.

### GitOps and Vault

Argo CD is installed by the platform layer, but nothing it runs is defined in
Terraform. The chain is handed over once, by hand:

```sh
terraform output -raw argocd_bootstrap_command   # kubectl apply -f gitops/bootstrap/root-app.yaml
```

From there the root Application reconciles everything under `gitops/apps/`,
which currently means the Vault PKI (sync wave 5) and Vault itself (wave 10).
Vault is deployed from the upstream Helm chart with values held in this
repository, through an Argo CD multi-source Application.

Terraform provides only what Vault cannot create for itself, in
`vault-aws-prerequisites`: the KMS auto-unseal key, the two IRSA roles, and the
Secrets Manager secret that receives the init output. The namespace and service
accounts are created by Terraform too, because the IRSA annotation contains the
AWS account ID and this repository is public. The Helm values therefore set
`server.serviceAccount.create = false`.

The unseal configuration references the KMS **alias**
(`alias/hashi-platform-dev-vault-unseal`), not the key ID. The alias is
deterministic and survives a rebuild of the environment, so no account-specific
identifier has to travel into `gitops/`.

**TLS** is issued by cert-manager, which the platform layer already installs.
`gitops/manifests/vault-pki` creates a self-signed CA, a CA issuer, and the
server certificate. The certificate covers `*.vault-internal` because the Raft
peers reach each other through the headless service as
`vault-0.vault-internal`; without those names `retry_join` with
`auto_join_scheme = "https"` fails certificate verification. For a
publicly reachable endpoint, swap the self-signed issuer for an ACME one and
the CA distribution problem disappears.

**The Enterprise license** is a Kubernetes secret created out of band. It must
never be committed:

```sh
terraform output -raw vault_license_secret_command
```

The chart mounts it and sets `VAULT_LICENSE_PATH` itself, so the Vault
configuration needs no entry for it. The license only loads on the Enterprise
image, which is why the values pin `hashicorp/vault-enterprise:<version>-ent`
rather than `hashicorp/vault`.

Vault's raft and audit volumes need a working StorageClass. EKS ships a `gp2`
class backed by the in-tree provisioner `kubernetes.io/aws-ebs`, which
Kubernetes removed in 1.31, and the EBS CSI addon brings none of its own — so
the platform layer creates an encrypted `gp3` class on `ebs.csi.aws.com` and
marks it default (`create_default_storage_class`). Without it every claim stays
`Pending` and the Vault pods never schedule.

After the first start the cluster still has to be initialised and unsealed
once, and an audit device enabled — `auditStorage` only provisions the volume.

### Reaching the UIs

Both control-plane UIs are published through internet-facing network load
balancers. The NLB passes TCP straight through, so Argo CD and Vault keep
terminating TLS themselves — no ACM certificate and therefore no domain is
needed. The trade-off is that both certificates are self-signed, so browsers
warn on the first visit.

```sh
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get svc vault-ui      -n vault  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Argo CD terminates TLS itself once it is behind a load balancer — the module
forces `server.insecure` off in that case, because the NLB passes TCP through
and a plain-HTTP backend would reset every handshake on 443, leaving only
unencrypted HTTP as a working path.

Argo CD listens on 443, Vault's UI on 8200 (`https://<hostname>:8200`). The
initial Argo CD password comes from
`terraform output -raw argocd_initial_admin_password`.

Both are open to `0.0.0.0/0` by default, which is a deliberate choice and not a
safe one: Argo CD can deploy anything into the cluster, and Vault is the secret
store. Narrow `argocd_allowed_cidr_blocks` in `dev.tfvars` and
`ui.loadBalancerSourceRanges` in `gitops/values/vault/values.yaml` as soon as
this is more than a sandbox. Each load balancer also costs roughly $16 a month.

### Monitoring

The platform layer also runs a Checkmk Raw server on a single EC2 instance in a
public subnet, installed and configured at first boot:

```sh
terraform output -raw checkmk_url                     # https://<eip>/cmk/
eval "$(terraform output -raw checkmk_admin_password_command)"
```

The interface is open to the internet over HTTPS with a **self-signed**
certificate, so browsers warn on the first visit; narrow
`checkmk_allowed_cidr_blocks` in `dev.tfvars` where you can. Shell access is
through SSM Session Manager, not SSH.

Two consequences of it living in the platform layer are worth knowing. It only
needs the VPC, yet the layer cannot plan at all without the EKS cluster, because
`data.aws_eks_cluster_auth` reads a live cluster. And the workspace auto-destroys
after a day without runs, which takes the monitoring history with it. If the
server should outlive the cluster, move it to the `cluster/` layer, which has the
VPC, no Kubernetes providers and a two-day window.

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
| Checkmk Raw Edition (.deb, Ubuntu 24.04 noble)                    | 2.4.0p36|
| Hardened base image (ami-prod `888995627335`)                     | latest  |

These are pinned inside the modules. Bump them there and run the unit tests
plus a plan in dev before rolling forward.

**The AWS provider and the terraform-aws-modules move together.** Those modules
declare an open lower bound on the provider (`eks` 20.8.5 says `aws >= 5.40`),
so Terraform will install a provider major the module predates and then fail on
schema the major removed — provider 6.x against `eks` 20.8.5 fails on the
`elastic_gpu_specifications` and `elastic_inference_accelerator` launch template
blocks that 6.0 dropped. In the other direction `eks` 21.x requires
`aws >= 6.59`. Neither bump works alone, so Dependabot groups them as
`aws-stack` and proposes one coordinated pull request; a provider major means
reviewing the upstream modules' own major upgrade guides at the same time. Dependabot tracks neither Helm charts
nor the Checkmk package; bump them by hand. Checkmk additionally pins the
package checksum, which has to be refreshed from the `.hash` sidecar in the same
change — see the
[module README](modules/aws-checkmk-server/README.md#upgrading-checkmk).
