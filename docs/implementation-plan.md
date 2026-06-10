# hashi-platform — Implementation Plan

> Detailed, dependency-ordered build plan. Each layer is one HCP Terraform workspace.
> Build strictly top-to-bottom — a layer's **Definition of done (DoD)** gates the next.
> Todos describe *what* to build, not *how* to code it.

**Legend:** `[ ]` todo · `→ outputs` feed later layers · **DoD** must pass before proceeding.

---

## Layer 0 — Bootstrap

**Goal:** Establish the accounts, automation, and trust relationships so every later
layer is fully code-driven. This is the only layer with deliberate manual setup.

**Depends on:** nothing.

- [x] Create the HCP organization and an HCP project named `hashi-platform`.
- [x] Create an HCP service principal for automation; record its credentials securely (this is the one bootstrap secret).
- [x] Create the AWS account/org structure and decide the region (`eu-central-1`).
- [x] Create the GitHub repository `hashi-platform` with branch protection on `main` (require PR + passing checks).
- [ ] Lay down the directory skeleton (one folder per layer + `modules/` + `docs/`).
- [ ] Create the HCP Terraform organization and one **workspace per layer**, each linked to its repo directory (VCS-driven).
- [ ] Configure **dynamic provider credentials (OIDC)** from HCP Terraform → AWS (IAM OIDC trust + scoped role).
- [ ] Configure **dynamic provider credentials (OIDC)** from HCP Terraform → HCP (so the HCP provider needs no static SP key in workspaces, where supported).
- [ ] Add the GitHub Actions workflow for the pre-merge gate: format check, validate, lint, security scan, plan preview.
- [ ] Decide and document the **CIDR plan** (VPC `10.0.0.0/16`, HVN `172.25.16.0/20`) — pin the HVN CIDR now.
- [ ] Define naming + tagging conventions (every resource tagged `project=hashi-platform`, `layer=`, `owner=`).

`→ outputs:` HCP project ID, OIDC role ARNs, workspace IDs, agreed CIDRs, tag standard.

**DoD:** A trivial change merged to `main` triggers an HCP Terraform run that authenticates
to AWS via OIDC with no static credentials anywhere; the GitHub Actions gate runs on PR.

---

## Layer 1 — Network

**Goal:** The VPC and private connectivity that everything else lands in.

**Depends on:** Layer 0 (OIDC to AWS, CIDR plan, tags).

- [ ] Create the VPC (`10.0.0.0/16`).
- [ ] Create 3 public + 3 private subnets, one pair per AZ (a, b, c).
- [ ] Create an internet gateway and one NAT gateway per AZ (or a single NAT to save cost in a demo — note the trade-off).
- [ ] Create route tables: public → IGW; private → NAT.
- [ ] Create the **HVN** (`172.25.16.0/20`) in HCP.
- [ ] Establish **HVN ↔ VPC peering**; accept the peering on the AWS side.
- [ ] Add routes on both sides for the opposite CIDR (VPC route table → HVN; HVN → VPC).
- [ ] Create role-based security groups (`consul-server`, `nomad-server`, `nomad-client`, `boundary-worker`) referencing each other by SG ID.
- [ ] On `nomad-server`, allow inbound `4646` **from the HVN CIDR** (for Vault JWKS validation later).
- [ ] Create scoped IAM instance profiles per node role (cloud auto-join read on EC2 tags, plus minimal extras).
- [ ] Capture the cluster auto-join tag key/value to be reused by Consul and Nomad.

`→ outputs:` VPC ID, subnet IDs (public/private per AZ), SG IDs, HVN ID, peering ID, instance profile ARNs, auto-join tag.

**DoD:** A throwaway instance in a private subnet can reach the internet via NAT and can
reach the HVN CIDR; the peering shows active on both sides.

---

## Layer 2 — Vault cluster (provision)

**Goal:** A running, privately-reachable Vault Dedicated cluster. Provisioning only —
configuration is Layer 3 (different lifecycle, smaller blast radius).

**Depends on:** Layer 1 (HVN, peering).

- [ ] Provision the HCP Vault Dedicated cluster in the HVN.
- [ ] Confirm the cluster uses its **private** endpoint (reached over peering), not public.
- [ ] Capture the Vault private address and namespace for downstream layers.
- [ ] Verify reachability of `:8200` from a private-subnet host across the peering.

`→ outputs:` Vault private address, namespace, cluster ID.

**DoD:** A private-subnet host can reach the Vault API over the peering on `8200`.

---

## Layer 3 — Vault configuration

**Goal:** Turn Vault into the identity and secrets authority for the whole platform.
This is the richest layer — treat each engine/auth method as code.

**Depends on:** Layer 2 (Vault reachable). Note: this layer is revisited as Layers 4–7 add
their specific roles/policies.

- [ ] Enable an **audit device** (file or CloudWatch).
- [ ] Enable the **JWT auth method** for Nomad workloads; configure its JWKS URL to resolve to multiple Nomad servers (deferred wiring until Layer 5, but define the method + `nomad-workloads` role now).
- [ ] Enable the **AWS secrets engine** for on-demand STS credentials; define roles for any workload AWS needs.
- [ ] Enable the **PKI engine(s)**: one for the Consul Connect mesh CA, one for SSH certificate signing (Boundary).
- [ ] Configure the PKI mounts (roots/intermediates, TTLs, allowed domains) for mesh and SSH.
- [ ] Enable the **database secrets engine**; prepare the PostgreSQL connection + role (the connection target lands in Layer 6 — define the structure now).
- [ ] Enable a **KV** mount for genuine static secrets.
- [ ] Write **least-privilege policies** per consumer (Nomad workload roles, Consul, Boundary credential brokering).
- [ ] Establish the auth path that **Consul** will use to retrieve its own secrets (gossip key, server TLS) — see Layer 4.

`→ outputs:` auth method paths, PKI mount paths + roles, AWS engine role names, DB engine mount, policy names.

**DoD:** Each engine and auth method is present and reproducible from the repo; a manual
test (e.g. issuing a cert from the mesh PKI role) succeeds.

---

## Layer 4 — Consul cluster

**Goal:** A secured 3-node Consul cluster acting as service catalog and mesh control
plane, with its Connect CA backed by Vault PKI.

**Depends on:** Layers 1 (network/SGs), 3 (Vault PKI + Consul auth path).

- [ ] Deploy the Consul server ASG (3 nodes, one per AZ) using **cloud auto-join** by tag.
- [ ] Bootstrap the **ACL system**; store the management token in Vault KV (never commit).
- [ ] Set the **default ACL policy to deny**.
- [ ] Enable **gossip encryption** (key sourced from Vault).
- [ ] Enable **TLS** for RPC + HTTP (server certs issued from Vault PKI).
- [ ] Configure Consul's **Connect CA provider to use the Vault PKI** mount from Layer 3.
- [ ] Verify a 3-node Raft quorum and leader election; confirm autopilot health.
- [ ] Enable Consul **audit logging**.

`→ outputs:` Consul server addresses, CA config reference, ACL token location (in Vault).

**DoD:** `consul members` shows 3 healthy servers across 3 AZs; the mesh CA reports
Vault as its provider; ACLs are default-deny.

---

## Layer 5 — Nomad cluster

**Goal:** A secured Nomad cluster integrated with both Consul (mesh/discovery) and Vault
(workload identity).

**Depends on:** Layers 1, 3 (Vault JWT method), 4 (Consul).

- [ ] Deploy the Nomad server ASG (3 nodes, one per AZ) with cloud auto-join.
- [ ] Deploy the Nomad client ASG (workload tier).
- [ ] Enable Nomad **ACLs**; bootstrap and store the management token in Vault.
- [ ] Integrate Nomad with **Consul** (service registration + Connect).
- [ ] Configure Nomad servers' **`default_identity`** (audience `vault`) for workload identity.
- [ ] Point Nomad clients at the Vault **JWT auth path** defined in Layer 3.
- [ ] **Wire the JWKS reachability:** confirm Vault (in HCP) can fetch `:4646/.well-known/jwks.json` over the peering, resolving to multiple Nomad servers.
- [ ] Verify a test job can exchange its workload identity for a scoped Vault token.
- [ ] Enable Nomad **audit logging**.

`→ outputs:` Nomad server/client addresses, confirmed workload-identity→Vault path.

**DoD:** Nomad shows 3 healthy servers + ≥1 client; a smoke-test job successfully
retrieves a secret from Vault via workload identity (no static Vault token used).

---

## Layer 6 — Reference workload

**Goal:** A real multi-component workload that exercises the mesh, intentions, and
dynamic secrets. (Tentative: PostgreSQL + Python web app — confirm before building.)

**Depends on:** Layers 4 (mesh), 5 (scheduling + workload identity), 3 (DB engine).

- [ ] Deploy **PostgreSQL** as a Nomad workload, registered in Consul with a Connect sidecar.
- [ ] Complete the Vault **database secrets engine** connection to this Postgres instance + a role that vends short-lived app credentials.
- [ ] Deploy the **Python web app** as a Nomad workload with a Connect sidecar.
- [ ] Configure the app to obtain its DB credentials from Vault **via workload identity** (no static DB password in the jobspec).
- [ ] Set Consul **intentions to default-deny**, then explicitly allow `web-app → postgres`.
- [ ] Verify end-to-end: the app connects to Postgres through the mesh using a short-lived, Vault-issued credential; removing the intention breaks the connection (proves enforcement).

`→ outputs:` service names, intention set, DB role name.

**DoD:** The app serves traffic using a dynamic DB credential; mesh mTLS is active;
intentions demonstrably gate service-to-service traffic.

---

## Layer 7 — Boundary

**Goal:** Identity-based human access to private nodes — no bastion, no keys — using
HCP-managed ingress and a self-managed egress worker.

**Depends on:** Layers 1 (private subnet + SG), 3 (Vault SSH PKI), workloads existing as targets.

- [ ] Provision the HCP **Boundary** cluster.
- [ ] Configure **OIDC auth** to the IdP for operator login.
- [ ] Deploy the **self-managed egress worker** in a private subnet; register it via **PKI**.
- [ ] Confirm the worker dials **outbound** to the HCP-managed ingress on `9202` (no inbound rules).
- [ ] Create **scopes** (org → project) mirroring intended team boundaries.
- [ ] Create a **dynamic AWS host catalog** that discovers targets by tag.
- [ ] Create **targets** with egress worker filters pointing at the self-managed worker.
- [ ] Configure **Vault credential brokering/injection** (Vault SSH engine signs a short-lived cert for the session).
- [ ] Verify end-to-end: operator logs in via OIDC, connects to a private node through ingress → egress, authenticated by a Vault-signed cert, holding no keys locally.

`→ outputs:` Boundary scope/target IDs, worker registration, credential library reference.

**DoD:** A login from a clean machine (no SSH keys) reaches a private target through
Boundary using a short-lived Vault-signed credential.

---

## Layer 8 — CI/CD hardening & observability

**Goal:** Production-grade pipeline and visibility; the operational finishing layer.

**Depends on:** all prior layers.

- [ ] Confirm the full pipeline: PR gate (validate/lint/scan/plan) + merge-triggered HCP Terraform apply per affected workspace.
- [ ] (Optional) Add **policy-as-code** (Sentinel/OPA) checks on HCP Terraform runs.
- [ ] Stand up **Prometheus**; wire Consul + Nomad telemetry.
- [ ] Build **Grafana** dashboards for mesh, scheduler, and Vault metrics.
- [ ] Schedule **Consul + Nomad snapshots** to S3; document the restore procedure.
- [ ] Document the **Vault** snapshot/restore path (HCP-managed).
- [ ] Write a short runbook: how to onboard a new service, rotate a credential, and recover a node.

**DoD:** Dashboards show live cluster health; a snapshot can be taken and a restore
rehearsed; the pipeline applies changes safely with a review gate.

---

## Milestones

1. **M1 — Foundation:** Layers 0–1 (code-driven, no static creds; network + peering live).
2. **M2 — Secrets authority:** Layers 2–3 (Vault running and configured).
3. **M3 — Platform runtime:** Layers 4–5 (Consul + Nomad secured and integrated).
4. **M4 — Live workload:** Layer 6 (app on the mesh with dynamic DB creds).
5. **M5 — Access + ops:** Layers 7–8 (Boundary access, observability, backups).

## Cross-cutting checks (apply at every layer)

- [ ] No static long-lived credential introduced anywhere.
- [ ] All configuration reproducible from the repo (nothing clicked in a UI).
- [ ] Resources tagged per the standard; least-privilege IAM/policies.
- [ ] Audit logging enabled where the component supports it.
- [ ] Change went through PR gate → HCP Terraform apply.