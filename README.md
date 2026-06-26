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
make fmt       # auto-format Terraform files
make help      # list all targets
```

## CI/CD

Runs are driven by GitHub Actions ([`.github/workflows/terraform.yml`](.github/workflows/terraform.yml))
against an **API-driven** HCP Terraform workspace:

1. `fmt -check` + `validate` run on every push and pull request.
2. On a **pull request**, a speculative HCP Terraform **plan** runs (no apply).
3. On **merge to `main`**, the config is uploaded and HCP Terraform **applies**
   it. Credentials are injected at run time via Vault dynamic credentials, so no
   long-lived AWS keys live in CI.

The pipeline holds **no static secrets**. The `plan` and `apply` jobs
authenticate to HCP Vault over **GitHub OIDC** (`hashicorp/vault-action`, JWT
mount `jwt-github`, role `gha-tfc`) and pull `TF_API_TOKEN` and
`TF_CLOUD_ORGANIZATION` from `secret/data/ci/tfc` at run time.

### Required configuration

| Where | Name | Value |
| --- | --- | --- |
| HCP Vault KV (`secret/data/ci/tfc`) | `TF_API_TOKEN` | HCP Terraform team/user API token |
| HCP Vault KV (`secret/data/ci/tfc`) | `TF_CLOUD_ORGANIZATION` | `tim-krebs-org` |
| Workflow `env` | `TF_WORKSPACE` | `hashi-platform-dev` |

On the **Vault** side, the `jwt-github` JWT auth mount must trust GitHub's OIDC
issuer with a `gha-tfc` role bound to this repo, and a policy granting read on
`secret/data/ci/tfc`. The CI jobs request `id-token: write` for this exchange.

On the **HCP Terraform** side, create the workspace with the **API-driven**
workflow (Remote execution), and configure Vault dynamic credentials
(`TFC_VAULT_PROVIDER_AUTH=true`, `TFC_VAULT_ADDR`, `TFC_VAULT_NAMESPACE`,
`TFC_VAULT_RUN_ROLE=tfc-role`) plus the JWT auth role in Vault. The `apply` job
is also bound to a `production` GitHub Environment, so you can require a manual
reviewer before any apply.

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
