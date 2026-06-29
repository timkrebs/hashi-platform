# hashi-platform

A hands-on platform-engineering project built on the HashiCorp stack: provision
infrastructure with **Terraform**, govern container/image versions with **HCP
Packer**, and deploy workloads to **Kubernetes (Amazon EKS)**.

> Note: This is a personal learning / portfolio project, not production-ready
> infrastructure. Provisioning the resources below will incur AWS costs.

## Repository layout

| Path | Description |
|------|-------------|
| [`infra/aws-eks/`](infra/aws-eks/) | Terraform configuration that provisions a VPC and an Amazon EKS cluster (Kubernetes 1.34, Amazon Linux 2023 managed node groups). |
| [`app/`](app/) | Application source + container build (work in progress). |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.7
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured with credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- An [HCP](https://portal.cloud.hashicorp.com/) account (for the HCP Packer steps)

## Getting started

1. Copy the environment template and fill in your own values:

   ```bash
   cp .env.example .env
   # then edit .env - it is gitignored and never committed
   ```

2. Provision the EKS cluster:

   ```bash
   cd infra/aws-eks
   terraform init
   terraform apply
   ```

3. Configure `kubectl` to talk to the new cluster:

   ```bash
   ./connect.sh
   kubectl get nodes
   ```

## Development

Run the local checks before every commit and push. These mirror what CI
enforces, so failures surface locally first:

```bash
make check     # fmt-check, validate, workflow YAML, and ASCII-only guard
make ci        # check + tflint + security scans (best effort locally)
make fmt       # auto-format Terraform files
make help      # list all targets
```

## Environments

The repo follows a three-stage promotion model. Each long-lived branch maps to
its own HCP Terraform workspace and GitHub Environment:

| Branch | Workspace | Environment | Gate |
| --- | --- | --- | --- |
| `dev` | `hashi-platform-dev` | `dev` | auto-apply |
| `staging` | `hashi-platform-staging` | `staging` | auto-apply |
| `main` | `hashi-platform-prod` | `production` | manual approval |

Changes flow `dev -> staging -> main`. A pull request runs a speculative plan
against the **base** branch's workspace; a merge applies to that workspace.

## CI/CD

Runs are driven by GitHub Actions ([`.github/workflows/terraform.yml`](.github/workflows/terraform.yml))
against **API-driven** HCP Terraform workspaces. Every push and pull request
runs these gates before any plan or apply:

| Gate | Tool | Purpose |
| --- | --- | --- |
| Format | `terraform fmt -check` | Consistent style |
| Validate | `terraform validate` | Syntactic and provider correctness |
| Lint | TFLint (+ AWS ruleset) | Provider best practices, deprecations |
| Misconfiguration | Trivy (`config`) | IaC security findings (HIGH/CRITICAL fail) |
| Secrets | Gitleaks | No committed credentials |

Only if all gates pass does the pipeline proceed:

1. On a **pull request**, a speculative HCP Terraform **plan** runs (no apply).
2. On **push to `dev`/`staging`/`main`**, the config is uploaded and HCP
   Terraform **applies** to the mapped workspace. `production` requires manual
   approval via its GitHub Environment.

A `concurrency` group per branch/PR prevents overlapping applies. Credentials
are never static: AWS access is issued at run time via HCP Terraform's Vault
dynamic credentials.

The pipeline holds **no static secrets**. The `plan` and `apply` jobs
authenticate to HCP Vault over **GitHub OIDC** (`hashicorp/vault-action`, JWT
mount `jwt-github`, role `gha-tfc`) and pull `TF_API_TOKEN` and
`TF_CLOUD_ORGANIZATION` from `secret/data/ci/tfc` at run time.

### Required configuration

| Where | Name | Value |
| --- | --- | --- |
| HCP Vault KV (`secret/data/ci/tfc`) | `TF_API_TOKEN` | HCP Terraform team/user API token |
| HCP Vault KV (`secret/data/ci/tfc`) | `TF_CLOUD_ORGANIZATION` | `tim-krebs-org` |

On the **Vault** side, the `jwt-github` JWT auth mount must trust GitHub's OIDC
issuer with a `gha-tfc` role bound to this repo, and a policy granting read on
`secret/data/ci/tfc`. The CI jobs request `id-token: write` for this exchange.

On the **HCP Terraform** side, create each workspace with the **API-driven**
workflow (Remote execution), and configure Vault dynamic credentials
(`TFC_VAULT_PROVIDER_AUTH=true`, `TFC_VAULT_ADDR`, `TFC_VAULT_NAMESPACE`,
`TFC_VAULT_RUN_ROLE=tfc-role`) plus the JWT auth role in Vault.

### Recommended branch protection

For an enterprise-grade setup, protect `staging` and `main` so the gates cannot
be bypassed:

- Require pull requests (no direct pushes) and at least one review.
- Require the `static`, `security`, and `plan` status checks to pass.
- Require branches to be up to date before merging.
- Add required reviewers to the `production` GitHub Environment.
- Enforce **Sentinel or OPA policy sets** at the HCP Terraform org/project
  level for cross-cutting guardrails (tagging, allowed regions, instance sizing)
  that run inside every plan.

## Ephemeral environments (dev / staging)

The `dev` and `staging` environments are ephemeral: stand them up for a load
test, then tear them down so they cost nothing while idle. Prod is excluded
from all teardown automation. Three layers cooperate:

1. **On-demand lifecycle** -
   [`ephemeral-env.yml`](.github/workflows/ephemeral-env.yml) (`workflow_dispatch`):
   - `up` - deploy and leave running for manual testing.
   - `down` - destroy when you are done.
   - `cycle` - deploy, run the [k6 load test](loadtest/k6-script.js), then
     **always destroy** (even if the test fails), so nothing is left running.

   ```bash
   gh workflow run ephemeral-env.yml \
     -f environment=dev -f action=cycle -f target_url=https://<app-endpoint>
   ```

2. **Scheduled backstop** -
   [`nightly-teardown.yml`](.github/workflows/nightly-teardown.yml) destroys
   any dev/staging infra left running. Manual by default; uncomment the `cron`
   to enable nightly teardown.

3. **Native HCP Terraform auto-destroy** (recommended TTL backstop). Set an
   inactivity-based auto-destroy on each ephemeral workspace so it self-destructs
   even if CI never runs:

   ```bash
   curl -sS --header "Authorization: Bearer $TF_API_TOKEN" \
     --header "Content-Type: application/vnd.api+json" --request PATCH \
     "https://app.terraform.io/api/v2/organizations/$TF_CLOUD_ORGANIZATION/workspaces/hashi-platform-dev" \
     --data '{"data":{"type":"workspaces","attributes":{"auto-destroy-activity-duration":"2d"}}}'
   ```

All teardown reuses the same Vault OIDC -> HCP Terraform path as the main
pipeline, and a destroy run is just a normal run with `is_destroy=true`.

## Roadmap

- [x] Provision EKS cluster with Terraform
- [x] Trigger HCP Terraform plan/apply from CI
- [ ] Containerize the demo app in [`app/`](app/)
- [ ] Build images with Packer and register metadata in HCP Packer
- [ ] Promote image versions via HCP Packer channels
- [ ] Deploy the channel-resolved image to EKS from CI

## License

Distributed under the Mozilla Public License 2.0. See [`LICENSE`](LICENSE).

The Terraform configuration under [`infra/aws-eks/`](infra/aws-eks/) is derived
from HashiCorp's [Provision an EKS Cluster](https://developer.hashicorp.com/terraform/tutorials/kubernetes/eks)
tutorial and retains its MPL-2.0 headers.
