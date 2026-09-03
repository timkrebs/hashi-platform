# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for the modules once they are tagged.

## [Unreleased]

### Added

- `aws-vpc` module: EKS-ready VPC with derived subnet layout, NAT options,
  load balancer subnet tags, input validation and plan-mode unit tests.
- `aws-eks-cluster` module: EKS control plane, typed managed node groups
  (capacity type, labels, taints), additional add-ons, EBS CSI driver with
  IRSA, input validation and plan-mode unit tests.
- `dev` environment root composing both modules against the
  `hashi-platform-dev` HCP Terraform workspace.
- GitHub Actions pipeline: static checks and speculative plan on pull
  requests, saved-plan apply behind environment protection on merge.
- Sentinel policy set under `infra/policies`: `require-mandatory-tags`
  (Environment, Project, ManagedBy on every taggable AWS resource) and
  `restrict-compute-size` (no instance type larger than medium), both
  hard-mandatory, with unit tests run in CI.
- Ephemeral dev and staging: `terraform-destroy.yml` destroys the source
  environment when a promotion pull request is merged (or on manual
  dispatch), and the dev and staging workspaces auto-destroy after one day
  without runs.
- `aws-eks-cluster` input `kms_key_deletion_window_in_days` (default 30);
  dev uses the 7-day minimum.
- Platform layer per environment (`infra/environments/<env>/platform`,
  workspace `hashi-platform-<env>-platform`): AWS Load Balancer Controller,
  cert-manager, Vault AWS prerequisites (KMS unseal key, IRSA roles, init
  secret), Argo CD with the in-cluster secret bridge, and the root
  Application syncing `gitops/clusters/<env>`. New modules with unit tests:
  `aws-load-balancer-controller`, `cert-manager`, `argocd`,
  `argocd-root-app`, `vault-aws-prerequisites`, `boundary` (placeholder).
- Composite action `hcp-workspace-state` and a shared plan-report script for
  the workflows.
- Repository scaffolding: shared tflint configuration, pre-commit hooks,
  Makefile, editorconfig, gitattributes, issue and pull request templates,
  CODEOWNERS, Dependabot for actions and Terraform.
- Contributor documentation: README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY.

### Changed

- Replaced the copied EKS tutorial configuration (embedded provider, fixed
  CIDRs and node groups) with the two modules above.
- Node groups default to Amazon Linux 2023 images; Amazon Linux 2 images are
  not published for Kubernetes 1.33 and later.
- IAM roles created for the cluster and node groups use deterministic names
  instead of random suffixes.
- Environment roots moved to `infra/environments/<env>/cluster`; the
  workflows, Makefile, `.gitignore` and Dependabot are layer-aware. The apply
  workflow applies the saved cluster plan and then plans and applies the
  platform layer inside the same approved job; the destroy workflow tears
  down platform before cluster and stops on failure.
- Staging VPC CIDR changed to `10.1.0.0/16`; cluster workspaces of ephemeral
  environments auto-destroy after 2 days, platform workspaces after 1 day.

### Removed

- Unused `random_string` resource and the `random` provider requirement.

[Unreleased]: https://github.com/timkrebs/hashi-platform/commits/dev
