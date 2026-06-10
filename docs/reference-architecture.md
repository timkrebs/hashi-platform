# hashi-platform — Reference Architecture

> A multi-product HashiCorp platform on AWS demonstrating an enterprise-grade,
> identity-first deployment of Vault, Boundary, Consul, and Nomad, provisioned
> entirely as code.

**Status:** Design — pre-implementation
**Owner:** Tim
**Region:** `eu-central-1` (Frankfurt), 3 Availability Zones (a, b, c)

---

## 1. Purpose & scope

`hashi-platform` is a self-built reference environment whose goal is to model how
the HashiCorp stack is deployed *in the field* — not a lab shortcut. Every design
choice optimises for two things: (1) demonstrable best practice, and (2) zero
long-lived static credentials anywhere in the system.

In scope:

- HCP Vault Dedicated — secrets management, PKI, dynamic credentials
- HCP Boundary — identity-based access to private targets (no bastion, no keys)
- Self-managed Consul — service catalog, service mesh, mesh CA
- Self-managed Nomad — workload scheduling
- HCP Terraform — all infrastructure and product configuration as code
- GitHub + GitHub Actions — source of truth and pre-merge validation gate
- A reference workload (tentative: PostgreSQL + a Python web application)

Out of scope (candidate Phase 2 items, see §11): multi-region, Transit Gateway,
multi-VPC Boundary multi-hop, Sentinel/OPA policy enforcement.

---

## 2. Design principles

1. **Identity is the spine.** No actor — CI pipeline, workload, service, or human —
   holds a long-lived credential. Every credential is short-lived and derived from a
   verifiable identity. Design the identity flows first (§6), the infrastructure second.

2. **Layered bootstrap.** The stack has inherent ordering dependencies (Vault must
   exist before Consul/Nomad can trust it; the network before any of them). These are
   resolved with explicit, separately-stated layers (§7), each its own Terraform
   workspace and state — never one monolithic apply.

3. **Configuration is code.** Vault, Consul, and Nomad configuration is managed
   declaratively, not clicked into a UI. If it isn't reproducible from the repo, it
   isn't done.

4. **Default deny.** ACLs enabled and default-deny on Consul and Nomad; Consul
   intentions default-deny; security groups reference identities/SGs over CIDRs where
   possible.

5. **Right-size to the topology.** Capability is added when the topology demands it,
   not pre-emptively (e.g. VPC peering now, Transit Gateway only if a second VPC arrives).

---

## 3. Locked decisions

| Area | Decision | Rationale |
|---|---|---|
| Terraform execution | HCP Terraform runs (VCS-driven) | Apply owned by HCP Terraform; dynamic provider credentials via OIDC mean no creds in CI |
| HVN connectivity | VPC peering | Point-to-point single VPC ↔ single HVN; no hourly/per-GB charge; least to operate |
| Boundary ingress | HCP-managed ingress + self-managed egress | No inbound path into the VPC; egress worker dials out only |
| Mesh CA | Vault-backed PKI (Consul Connect CA → Vault) | Single root of trust for human PKI and mesh PKI |
| Reference workload | PostgreSQL + Python web app *(tentative)* | DB gives a real dynamic-secrets story; ≥2 components exercise the mesh + intentions |
| CI gate | GitHub Actions (validate / lint / scan / plan preview) | Merge triggers the HCP Terraform run |

---

## 4. Component inventory

| Component | Hosting | Role |
|---|---|---|
| Vault Dedicated | HCP (managed) | Secrets, PKI (mesh + SSH), AWS secrets engine, KV, audit |
| Boundary control plane | HCP (managed) | Authn (OIDC to IdP), session brokering, host catalogs, targets |
| HCP-managed ingress worker | HCP (managed) | Client-facing entry point for Boundary sessions |
| Consul servers | AWS EC2 (ASG, 3 nodes) | Service catalog, mesh control plane, Connect CA (Vault-backed) |
| Nomad servers | AWS EC2 (ASG, 3 nodes) | Scheduling, workload-identity signing (JWKS issuer) |
| Nomad clients | AWS EC2 (ASG) | Run the reference workload + Consul Connect sidecars |
| Boundary egress worker | AWS EC2 (private subnet) | Reverse-proxy to private targets; PKI auth; outbound only |
| Reference workload | Nomad allocations | PostgreSQL + Python web app behind the mesh |

Server clusters are sized at 3 for quorum (tolerates one node loss) and spread one per
AZ. Scale to 5 if you want to demonstrate a larger failure domain.

---

## 5. Network architecture

### 5.1 CIDR plan (pin before building)

The HVN CIDR **cannot be changed** after creation without a rebuild, so fix it first
and ensure it never overlaps the VPC.

| Network | CIDR | Notes |
|---|---|---|
| VPC | `10.0.0.0/16` | Primary workload network |
| HVN | `172.25.16.0/20` | HCP-managed; default range, non-overlapping |

### 5.2 Subnets (per AZ, 3 AZs)

| Tier | Example CIDRs | Contents |
|---|---|---|
| Public | `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24` | NAT gateways only |
| Private | `10.0.10.0/24`, `10.0.11.0/24`, `10.0.12.0/24` | Consul, Nomad servers/clients, Boundary egress worker |

All stateful and compute nodes live in private subnets. Public subnets exist only to
host NAT for outbound. There is no bastion — Boundary replaces it. Size private subnets
larger (`/22`) if you expect many Nomad client nodes.

### 5.3 Connectivity

- **HVN ↔ VPC peering** connects HCP Vault Dedicated's private endpoint to the VPC.
  Route tables on both sides carry routes to the opposite CIDR.
- **Vault** is reached privately over the peering on `8200`.
- **Boundary egress worker** makes **outbound** connections only: to the HCP-managed
  ingress worker on `9202`, and to targets within the VPC. No inbound rules required.
- **NAT gateways** provide outbound internet for nodes (package installs, HCP control
  plane reachability).

### 5.4 Security groups (by role, SG-referencing)

| SG | Inbound (summary) |
|---|---|
| `consul-server` | Serf 8301/8302 (TCP+UDP), server RPC 8300, HTTP(S) 8500/8501, gRPC 8502, DNS 8600 — from cluster SGs |
| `nomad-server` | HTTP 4646 (incl. JWKS), RPC 4647, serf 4648 (TCP+UDP) — from cluster SGs **and `4646` from the HVN CIDR** |
| `nomad-client` | Dynamic ports + Connect sidecar range 21000–21255 — from cluster SGs |
| `boundary-worker` | None required (outbound-only); allow egress to HCP + targets |

> **Critical detail:** Vault's JWT auth method validates Nomad workload identities by
> fetching Nomad's JWKS endpoint (`:4646/.well-known/jwks.json`). Because Vault runs in
> HCP, the `nomad-server` SG must allow inbound `4646` **from the HVN CIDR**, and the
> JWKS URL must resolve to multiple Nomad servers (not a single node) so it isn't a SPOF.

---

## 6. Identity & trust architecture

Five flows, none using a static long-lived credential.

### 6.1 CI / IaC → cloud (provisioning)

HCP Terraform owns the apply. It uses **dynamic provider credentials** (OIDC) to
authenticate to AWS and to HCP/Vault, so no access keys or tokens are stored in CI or
in the workspace. GitHub Actions never holds cloud credentials — it runs the pre-merge
gate (fmt, validate, lint, security scan, plan preview); merge to `main` triggers the
HCP Terraform run for the affected workspace.

### 6.2 Application AWS access (if needed at runtime)

Where a workload needs AWS access, Vault's **AWS secrets engine** vends short-lived STS
credentials on demand — pulled at use time, never synced and stored.

### 6.3 Workload → Vault (Nomad workload identity)

- Nomad servers issue a signed JWT **workload identity** per task (audience `vault`)
  via `default_identity`.
- Vault has a **JWT auth method** whose config points at Nomad's JWKS URL, plus a
  `nomad-workloads` role mapping identities to scoped policies.
- Jobspecs reference a Vault **role** (not a policy). The reference workload uses this
  to obtain short-lived PostgreSQL credentials from Vault's **database secrets engine**.
- This is the current pattern (Nomad 1.10+); the legacy token-based integration is not used.

### 6.4 Service → service (Consul Connect)

- Connect issues SPIFFE mTLS identities to each service; sidecar proxies enforce mTLS.
- **Intentions** are the authorization layer, running **default-deny** — traffic is
  explicitly allowed per service pair.
- The **Connect CA is backed by Vault PKI**, making Vault the single root of trust.

### 6.5 Human → target (Boundary)

- Operator authenticates to Boundary via **OIDC** to the IdP (no shared keys).
- Boundary brokers/injects a credential from Vault (e.g. Vault SSH engine signs a
  short-lived certificate).
- Session is proxied: client → HCP-managed ingress worker → self-managed egress
  worker → target. The egress worker initiates the connection outbound.
- Targets are discovered via a **dynamic AWS host catalog** (by tag) — no hand-maintained host list.

---

## 7. Layering model (state isolation)

Each layer is a separate HCP Terraform workspace with its own state, mapped to a repo
directory. Layers consume the published outputs of earlier layers. This both resolves
the bootstrap ordering and bounds blast radius (a workload change cannot affect the network).

```
0  bootstrap        HCP org/project, workspaces, OIDC trust, repo skeleton
1  network          VPC, subnets (3 AZ), NAT, routes, SGs, HVN, peering
2  vault-cluster    HCP Vault Dedicated provisioning
3  vault-config     audit, JWT auth, AWS engine, PKI (mesh + SSH), DB engine, KV, policies
4  consul           server ASG, ACLs, gossip+TLS, Connect CA -> Vault PKI
5  nomad            server + client ASGs, ACLs, Consul + Vault (workload identity) integ.
6  workloads        Postgres + Python app, Connect sidecars, default-deny intentions
7  boundary         HCP cluster, egress worker, scopes, AWS host catalog, targets, Vault creds
8  cicd-observe     pipeline hardening, Prometheus/Grafana, snapshot jobs
```

Build strictly top-to-bottom; each layer's "Definition of done" gates the next (see the
implementation plan).

---

## 8. Reference topology

```
        ┌─────────────────────────┐        ┌──────────────────────────┐
        │  CI / IaC pipeline       │        │  Operator (human)        │
        │  GitHub Actions ·        │        │  OIDC · no SSH keys      │
        │  HCP Terraform runs      │        └────────────┬─────────────┘
        └────────────┬────────────┘                     │ OIDC
              OIDC    │  (dynamic provider creds)        │
                      ▼                                  ▼
        ┌──────────────────────────────── HCP (managed) ───────────────────────────┐
        │   ┌──────────────────────┐         ┌──────────────────────────────────┐  │
        │   │  Vault Dedicated     │         │  Boundary control plane          │  │
        │   │  secrets · PKI ·     │         │  + HCP-managed ingress worker    │  │
        │   │  dynamic creds       │         │  session brokering               │  │
        │   └──────────┬───────────┘         └──────────────┬───────────────────┘  │
        └──────────────┼────────────────────────────────────┼─────────────────────┘
                       │ HVN peering (8200, private)         │ 9202 (egress dials out)
        ┌──────────────┼────────────────────────────────────┼─────────────────────┐
        │ AWS VPC 10.0.0.0/16 — private subnets, 3 AZs       │                     │
        │              ▼                                     ▲                     │
        │  ┌───────────────┐  ┌───────────────┐   ┌──────────┴──────────┐         │
        │  │ Consul servers│  │ Nomad servers │   │ Boundary egress     │         │
        │  │ mesh · catalog│  │ schedulers ·  │   │ worker (PKI)        │         │
        │  │ Connect CA    │  │ JWKS issuer   │   └─────────────────────┘         │
        │  └───────────────┘  └───────────────┘                                   │
        │  ┌──────────────────────────────────────────────────────────┐          │
        │  │ Nomad clients (workload tier)                            │          │
        │  │ PostgreSQL + Python web app · Consul Connect sidecars    │          │
        │  └──────────────────────────────────────────────────────────┘          │
        └─────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Non-functional / enterprise requirements

- **High availability:** odd-sized server quorums (3 or 5) spread across AZs; Raft
  autopilot enabled; Vault HA handled by HCP.
- **Zero static trust:** ACLs enabled + default-deny (Consul, Nomad); intentions
  default-deny; gossip encryption; TLS on all RPC/HTTP; mTLS in the mesh.
- **Bootstrap trust:** every layer's "secret zero" handled explicitly — initial ACL
  management tokens stored in Vault and retrieved by the next layer's automation, never committed.
- **Audit:** Vault audit device (to file/CloudWatch); Consul + Nomad audit logging;
  Boundary session recording (optional, for the full PAM story).
- **Least privilege:** scoped IAM instance profiles per node role; narrow Vault
  policies per workload role; Boundary scopes (org → project) mirroring team boundaries.
- **Backup / DR:** scheduled Consul + Nomad snapshots to S3; Vault snapshots
  HCP-managed (understand the restore path).
- **Observability:** Consul + Nomad telemetry to Prometheus; Grafana dashboards for
  mesh, scheduler, and Vault metrics.

---

## 10. Repository & pipeline structure

Mono-repo, one directory per layer mapped to a dedicated HCP Terraform workspace, plus a
shared `modules/` directory for reusable building blocks.

```
hashi-platform/
├── docs/
│   ├── reference-architecture.md
│   └── implementation-plan.md
├── modules/                 # reusable: consul-asg, nomad-asg, boundary-worker, network
├── 0-bootstrap/
├── 1-network/
├── 2-vault-cluster/
├── 3-vault-config/
├── 4-consul/
├── 5-nomad/
├── 6-workloads/
├── 7-boundary/
├── 8-cicd-observe/
└── .github/workflows/       # validate / lint / scan / plan on PR
```

Pipeline: PR opens → GitHub Actions runs `fmt` check, `validate`, lint, security scan,
and a plan preview → review → merge to `main` triggers the HCP Terraform apply for the
affected workspace(s). Cross-layer dependencies flow via published workspace outputs.

---

## 11. Future phases (documented, not built day one)

- **Transit Gateway + second VPC** — introduce when a second (workload) VPC arrives.
  The natural trigger is the Boundary **multi-hop** demo: a workload VPC reached through
  a shared-services VPC makes the ingress → intermediary → egress chain real. Migration
  from peering is mechanical (swap attachment, add RAM share + TGW route tables).
- **Multi-region** Vault performance/DR replication topology.
- **Policy as code** — Sentinel or OPA gates on HCP Terraform runs.
- **Boundary session recording** for full privileged-access auditing.