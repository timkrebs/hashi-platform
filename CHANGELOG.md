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
  `hashi-platform-dev` HCP Terraform workspace, driven from `main`.
- GitHub Actions pipeline: static checks and speculative plan on pull
  requests, saved-plan apply behind environment protection on merge.
- Sentinel policy set under `infra/policies`: `require-mandatory-tags`
  (Environment, Project, ManagedBy on every taggable AWS resource) and
  `restrict-compute-size` (no instance type larger than medium), both
  hard-mandatory, with unit tests run in CI.
- Ephemeral dev: `terraform-destroy.yml` tears the environment down on manual
  dispatch, and the dev workspaces auto-destroy after a day without runs.
- `aws-eks-cluster` input `kms_key_deletion_window_in_days` (default 30);
  dev uses the 7-day minimum.
- Platform layer (`infra/environments/dev/platform`, workspace
  `hashi-platform-dev-platform`): AWS Load Balancer Controller and
  cert-manager. New modules with unit tests:
  `aws-load-balancer-controller`, `cert-manager`, `boundary` (placeholder).
- `aws-checkmk-server` module: Checkmk Raw Edition 2.4.0p36 on an Ubuntu 24.04
  EC2 instance in a public subnet, with an elastic IP, an encrypted gp3 root
  volume, IMDSv2-only metadata and SSM Session Manager access instead of an SSH
  key pair. The package is verified against a pinned SHA256 at first boot, and
  the interface is served over HTTPS with a self-signed certificate while port
  80 redirects to 443.
- The initial `cmkadmin` password is generated with `random_password`, stored as
  an SSM `SecureString`, and read by the instance from SSM at boot through its
  instance profile, so it never appears in user data. The `random` provider is
  required again.
- Platform layer wires the monitoring server behind `enable_checkmk`, with
  `checkmk_instance_type` and `checkmk_allowed_cidr_blocks` inputs and outputs
  for the URL, the elastic IP, the instance ID and the commands that read the
  password and open a Session Manager shell.
- `public_subnet_ids` and `vpc_cidr_block` added to the platform layer's remote
  state `defaults`, so plans still work before the cluster workspace has state.
- Hardened images from the company ami-prod account (`888995627335`) for
  compliance. The Checkmk server runs on `hc-base-ubuntu-2404-amd64-*`, and
  `aws-eks-cluster` gains `use_hardened_node_ami`, `node_ami_owner` and
  `node_ami_architecture` to run managed node groups on
  `hc-base-ubuntu-2404-eks-<version>-amd64-*`.
- Hardened nodes pass `--resolv-conf=/run/systemd/resolve/resolv.conf` to
  kubelet (`node_bootstrap_extra_args`). Ubuntu's systemd-resolved stub would
  otherwise reach every pod as `127.0.0.53`, making CoreDNS forward to itself
  and abort with "loop detected", which takes cluster DNS down entirely.
- The EKS node image is selected by `cluster_version`, so it cannot drift ahead
  of the control plane; a version with no published image fails the plan rather
  than creating nodes that never join. Custom images also need
  `enable_bootstrap_user_data`, because EKS injects no bootstrap for them.
- Argo CD is installed by the platform layer again, and the `gitops/` tree it
  reconciles: a root Application applied once by hand, the Vault PKI, and Vault
  itself from the upstream Helm chart through a multi-source Application.
- `vault-aws-prerequisites` is restored for the in-cluster Vault: KMS
  auto-unseal key, IRSA roles and the Secrets Manager secret for the init
  output. The platform layer also creates the Vault namespace and its service
  accounts, because the IRSA annotation carries the AWS account ID and this
  repository is public.
- Default encrypted `gp3` StorageClass on `ebs.csi.aws.com`
  (`create_default_storage_class`). The `gp2` class EKS ships uses the in-tree
  provisioner Kubernetes removed in 1.31, and the EBS CSI addon ships no class
  of its own, so every PersistentVolumeClaim stayed `Pending`.
- `aws-load-balancer-controller` grants
  `elasticloadbalancing:DescribeListenerAttributes` and
  `ModifyListenerAttributes` on top of the bundled upstream policy, which
  predates the controller version the chart installs. Without them every
  `LoadBalancer` service hangs on `<pending>` and the cause is only visible in
  the controller log.
- Argo CD forces `server.insecure` off when `service_type` is `LoadBalancer`.
  The NLB passes TCP through, so a plain-HTTP backend resets every TLS
  handshake on 443 and only unencrypted HTTP would work.
- The Argo CD and Vault UIs are published through internet-facing network load
  balancers (`argocd_service_type`, `argocd_allowed_cidr_blocks`, and `ui.*` in
  the Vault values). The NLBs pass TCP through so both keep terminating TLS
  themselves, which avoids needing a domain and an ACM certificate at the cost
  of a self-signed certificate warning. Both default to `0.0.0.0/0`.
- Vault's `retry_join` sets `leader_ca_cert_file`. Without it a joining node
  verifies the leader against the system CAs, fails with `certificate signed by
  unknown authority`, and the cluster stays at one peer while the other pods sit
  at `0/1` with no outward sign of the cause.
- Vault TLS is issued by cert-manager from `gitops/manifests/vault-pki`. The
  certificate covers `*.vault-internal` so Raft peers can verify each other.
- `config/vault/` ships the Vault CA as `vault-ca.pem` and trusts it by
  default. Reaching Vault needs both a trusted CA and a matching name, and the
  two fail with different errors; neither can be solved from a runner that has
  never seen the cluster. The file carries no private key. A rebuilt environment
  regenerates the CA and the copy has to be refreshed.
- `config/vault/` takes `vault_tls_server_name`, so the provider can verify
  Vault's certificate against an in-cluster name while connecting through the
  load balancer, whose generated hostname the certificate does not carry.
- `config/vault/`: a Terraform root that configures the running Vault cluster.
  An `admin` policy and userpass login in the root namespace so the root token
  can be revoked; the `hp-dev-backend` and `hp-dev-frontend` namespaces, each
  with its own userpass auth, policy and kv-v2 engine; a root CA that signs both
  an intermediate in the root namespace and a `pki-dev` engine inside the
  backend namespace, so developers issue their own certificates without ever
  seeing the root key. Passwords are inputs; only the two demo API keys are
  generated. `make check` covers the new root through `CONFIG_DIRS`.
- `terraform-plan.yml` and `terraform-apply.yml` are replaced by a single
  `terraform.yml` that runs on pull requests and on pushes to `main`. Its jobs
  are chained — fmt, tflint, validate, test, policies, resolve, plan, apply — so
  a failure lands in one named box instead of somewhere inside a combined
  "static checks" job.
- The pipeline plans and applies `config/vault` after the platform layer, and
  posts a speculative Vault plan on pull requests. The stage carries no
  `-var-file`, and is skipped until the `hashi-platform-vault` workspace exists.
- `auth-service`: a reference microservice under `kubernetes/apps/`. It issues
  short-lived RS256 JWTs, verifies credentials against Vault's userpass auth,
  and signs with Vault's Transit engine, so the private key is generated inside
  Vault and never leaves it — a compromised pod cannot mint tokens once its
  Vault token is gone. Verification is decentralised through
  `/.well-known/jwks.json`, so no other service calls this one on the request
  path. Structured JSON logs, bounded-cardinality Prometheus metrics, split
  public and admin listeners, PodDisruptionBudget, `restricted` Pod Security,
  and unit tests covering the token contract.
- `config/vault/kubernetes-auth.tf`: the `kubernetes` auth backend in the
  `hp-dev-backend` namespace, a Transit mount with a non-exportable RSA key, a
  policy and a role bound to one ServiceAccount in one Kubernetes namespace.
  This is what the Vault Agent Injector needed to authenticate a pod — it was
  running, but Vault had only `userpass`, so no workload could log in.
- Observability in the cluster: `kube-prometheus-stack` (Prometheus,
  Alertmanager, node-exporter, kube-state-metrics and Grafana), `loki` as the
  log store and `alloy` as the collector, all reconciled by Argo CD. Grafana is
  published through its own load balancer.
- Argo CD no longer rewrites the Grafana admin password. The chart regenerates
  it with `randAlphaNum 40` on every render, so each sync wrote a fresh value
  into the Secret while Grafana keeps the password it was given at first start
  in `grafana.db` on its PVC. The login then failed with a password that had
  been read correctly. The Secret's `admin-password` and `admin-user` are now
  under `ignoreDifferences` with `RespectIgnoreDifferences=true`, which is
  needed because `ignoreDifferences` alone only affects the diff and a sync
  would still write the field.
- Two Grafana dashboards, reconciled by Argo CD as ConfigMaps that the chart's
  dashboard sidecar picks up: `SRE Overview` (cluster, Vault, workloads,
  resources on one page) and `Vault Enterprise` (seal state, Raft, leases,
  audit, leadership). They land in the `General` folder; the `grafana_folder`
  annotation on the ConfigMaps only takes effect once
  `grafana.sidecar.dashboards.folderAnnotation` is set in the chart values.
  Every query was run against Prometheus before committing, so no panel is
  wired to a metric this cluster does not emit.
- `SRE Overview` leads with used pod slots against allocatable, because the
  pod ceiling — not CPU or memory — is what this cluster runs out of first:
  `t3.medium` allows 17 pods per node, and three full nodes leave Loki and the
  third Vault replica unschedulable.
- Vault gains a second listener on 8202 that exists only inside the cluster,
  with `unauthenticated_metrics_access` enabled on it. It stays disabled on
  8200, which the load balancer publishes to the internet. Prometheus scrapes
  the pod IPs directly, because the chart declares no container port for 8202.
- An `import` block adopts the `logging` namespace Argo CD had already created.
  `terraform import` is unavailable with remote execution, and an import block
  whose target is already managed is a no-op, so it is safe to leave in place.
- The Fluent Bit Application does not create its namespace: the platform layer
  owns it, because the service account in it needs an IRSA annotation carrying
  the AWS account ID. With both creating it, whichever ran second failed.
- `aws-fluent-bit-cloudwatch` module and its Application: a durable copy of the
  container logs outside the cluster, alongside the searchable copy in Loki. The
  log group and its retention are Terraform's, and the IAM policy omits
  `logs:CreateLogGroup` so no second group can appear without one.
- Composite action `hcp-workspace-state` and a shared plan-report script for
  the workflows.
- `.terraform-version` pinning Terraform to 1.15.9, so tenv and friends select
  the version the environment roots require instead of a newer minor that
  fails `terraform init`.
- Repository scaffolding: shared tflint configuration, pre-commit hooks,
  Makefile, editorconfig, gitattributes, issue and pull request templates,
  CODEOWNERS, Dependabot for actions and Terraform.
- Contributor documentation: README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY.

### Changed

- Dev cluster moves to Kubernetes 1.34 as the first of three steps towards 1.35,
  where the hardened EKS node image is published. EKS upgrades one minor version
  per apply, and no hardened image exists for 1.34, so the nodes stay on AL2023
  until the cluster reaches 1.35.
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
- The cluster workspace auto-destroys after 2 days, the platform workspace
  after 1, so the platform layer is always torn down first.
- Dependabot groups the AWS provider with the `terraform-aws-modules` registry
  modules as `aws-stack`, because neither can be bumped across a major on its
  own: the modules declare an open lower bound on the provider, so a provider
  major installs against a module that predates it and fails on removed schema.
- Dependabot no longer proposes majors of the AWS provider or the
  `terraform-aws-modules`, and now also watches `config/`. The grouped bump to
  provider 6.x, `eks` 21.x, `iam` 6.x and `vpc` 6.x cannot merge: `eks` 21.x
  renames every argument the cluster module passes and drops
  `eks_managed_node_group_defaults`, and `iam` 6.x deletes
  `iam-assumable-role-with-oidc` and renames `iam-role-for-service-accounts-eks`,
  which four modules use. It is a migration, so it is written down as one in
  `infra/README.md` instead of reappearing as a red pull request every week.

### Removed

- The Checkmk agents left behind in the cluster. Removing an Argo CD
  Application does not remove what it deployed unless the Application carries
  `resources-finalizer.argocd.argoproj.io`, so `checkmk-monitoring` kept running
  two DaemonSets, a collector and an internet-facing load balancer with nothing
  managing them. They held seven pod slots — two on every node — which is what
  kept the third Vault replica, Loki and an admission job unschedulable.
- Checkmk in full: the `aws-checkmk-server` module, its wiring in the platform
  layer, the `checkmk-kube-agent` Application, the monitoring AppRole in
  `config/vault` and `config/checkmk/`. Its site configuration could not be
  managed declaratively — no Terraform provider exists — and it stores no log
  history, both of which the Grafana stack settles. The EC2 instance and its
  elastic IP go with it.

- The `staging` and `production` environments (`infra/environments/staging`,
  `infra/environments/production`) and their HCP Terraform workspaces from the
  pipeline. The repository now runs a single `dev` environment.
- The branch-per-environment model. `main` is the only long-lived branch; the
  workflows trigger on it and target `dev` directly, and the promotion-driven
  destroy trigger is gone (the destroy workflow is manual dispatch only).
- The `argocd-root-app` module. The root Application now lives in
  `gitops/bootstrap/` and is applied once by hand, so Terraform does not
  duplicate it.
- The in-cluster secret bridge (`hashi-platform.io/*` annotations on the Argo CD
  cluster secret). Account-specific values reach Vault through the service
  account annotation Terraform sets instead, and the unseal key is referenced by
  its deterministic KMS alias.
- Unused `random_string` resource and the `random` provider requirement.

[Unreleased]: https://github.com/timkrebs/hashi-platform/commits/main
