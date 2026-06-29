# Boundary + Vault credential store (SSH key brokering)

A runbook for configuring **HCP Vault as a static credential store for HCP
Boundary**, so Boundary injects an **SSH private key** into sessions. The key is
stored only in Vault; the connecting user never sees it.

This is a manual setup (CLI/console) against HCP Boundary and HCP Vault. Nothing
in this repository is applied by following it.

References:

- [Static credentials with Vault](https://developer.hashicorp.com/boundary/docs/credentials/static-cred-vault)
- [HCP Vault credential brokering quickstart](https://developer.hashicorp.com/boundary/tutorials/credential-management/hcp-vault-cred-brokering-quickstart)
- [Boundary Vault integration](https://developer.hashicorp.com/boundary/docs/vault)

## How it fits together

```
  Operator                HCP Boundary                  HCP Vault
  --------                ------------                  ---------
  boundary connect ssh -> target (ssh) ----------------> credential store (vault)
                              |                              |
                              | egress worker filter         | reads KV secret
                              v                              v
                       in-cluster worker  --- ssh:22 --->  EC2 host / EKS node
                       (key injected)
```

Boundary authenticates to Vault with a periodic token, reads the SSH key from a
KV path, and **injects** it into the SSH session brokered through the worker
running inside the cluster.

## Naming conventions

Adopt these consistently. The guiding idea: **a Boundary org is the team/platform;
a Boundary project is one environment** (the boundary where targets and
credential stores live). Vault paths and policies are namespaced per project so a
project's token can only read its own secrets.

| Resource | Convention | Example |
| --- | --- | --- |
| Boundary org scope | platform / team name | `hashi-platform` |
| Boundary project scope | one per environment | `eks-dev`, `eks-staging`, `eks-prod` |
| Vault namespace | HCP working namespace | `admin/hcp-platform` |
| Vault KV secret path | `secret/boundary/<project>/<cred>` | `secret/boundary/eks-dev/node-ssh` |
| Vault policy (shared) | fixed name | `boundary-controller` |
| Vault policy (read) | `boundary-<project>-read` | `boundary-eks-dev-read` |
| Vault token | periodic + orphan + renewable, one per credential store | n/a |
| Boundary credential store | `vault-<project>` | `vault-eks-dev` |
| Boundary credential library | `<resource>-<credtype>` | `node-ssh-key` |
| Boundary target | `<resource>-<protocol>` | `node-ssh` |
| Boundary worker | `<cluster>-worker`, tags `type` / `env` / `cluster` / `region` | `env = ["dev"]` |
| Boundary account | lowercase username | `tim.krebs` |
| Boundary group | `<scope>-<role>` | `eks-dev-operators` |
| Boundary role | `<project>-<capability>` | `eks-dev-ssh` |

## Prerequisites

- The `vault` and `boundary` CLIs, plus `jq`.
- HCP Vault: address, the `admin/hcp-platform` namespace, and an admin token.
- HCP Boundary: cluster address and an admin login (password auth method id).
- A self-managed Boundary **worker** running in the cluster, tagged so its
  `env` tag matches the target's egress filter (e.g. `env = ["dev"]`) and able to
  reach the SSH host on port 22.
- The SSH private key file you want Boundary to broker (e.g. `eks-dev-node-ssh.pem`).

## Part A - Vault (namespace `admin/hcp-platform`)

```bash
export VAULT_ADDR="https://hashi-vault-euc1-public-vault-24f28885.731bdaf0.z1.hashicorp.cloud:8200"
export VAULT_NAMESPACE="admin/hcp-platform"
# export VAULT_TOKEN=<your admin token>

# 1. Store the SSH key in the KV v2 mount 'secret'. The field names 'username'
#    and 'private_key' are what the ssh_private_key credential type expects.
vault kv put secret/boundary/eks-dev/node-ssh \
  username=ec2-user \
  private_key=@./eks-dev-node-ssh.pem

# 2. The boundary-controller policy lets Boundary manage its own token and leases.
vault policy write boundary-controller - <<'EOF'
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/renew-self"  { capabilities = ["update"] }
path "auth/token/revoke-self" { capabilities = ["update"] }
path "sys/leases/renew"       { capabilities = ["update"] }
path "sys/leases/revoke"      { capabilities = ["update"] }
path "sys/capabilities-self"  { capabilities = ["update"] }
EOF

# 3. A per-project read policy (least privilege - only this project's secrets).
vault policy write boundary-eks-dev-read - <<'EOF'
path "secret/data/boundary/eks-dev/*"     { capabilities = ["read"] }
path "secret/metadata/boundary/eks-dev/*" { capabilities = ["list", "read"] }
EOF

# 4. Create the token Boundary uses for this credential store. It MUST be
#    periodic, orphan, and renewable. Save the output as CRED_STORE_TOKEN.
vault token create -no-default-policy=true \
  -policy=boundary-controller \
  -policy=boundary-eks-dev-read \
  -orphan=true -period=20m -renewable=true -field=token
```

## Part B - Boundary

```bash
export BOUNDARY_ADDR="https://<cluster-id>.boundary.hashicorp.cloud"
boundary authenticate password -auth-method-id ampw_xxxxxxxx -login-name <admin>

# Scopes: global -> org -> project
ORG_ID=$(boundary scopes create -scope-id global \
  -name hashi-platform -description "Platform org" \
  -format json | jq -r .item.id)

PROJ_ID=$(boundary scopes create -scope-id "$ORG_ID" \
  -name eks-dev -description "EKS dev environment" \
  -format json | jq -r .item.id)

# Vault credential store. -vault-namespace is required for HCP Vault.
CS_ID=$(boundary credential-stores create vault -scope-id "$PROJ_ID" \
  -name vault-eks-dev \
  -vault-address "$VAULT_ADDR" \
  -vault-namespace "admin/hcp-platform" \
  -vault-token "$CRED_STORE_TOKEN" \
  -format json | jq -r .item.id)

# Credential library. For a KV v2 mount the path MUST include 'data/'.
CL_ID=$(boundary credential-libraries create vault-generic \
  -credential-store-id "$CS_ID" \
  -name node-ssh-key \
  -credential-type ssh_private_key \
  -vault-path "secret/data/boundary/eks-dev/node-ssh" \
  -format json | jq -r .item.id)

# SSH target. The egress worker filter pins sessions to this environment's
# in-cluster worker via its 'env' tag.
#
# Set NODE_ADDRESS to a real host the worker can reach - e.g. a node's
# INTERNAL-IP from `kubectl get nodes -o wide`. Do NOT paste a literal <...>
# placeholder: the shell reads '<' as input redirection and errors.
NODE_ADDRESS="10.0.1.23" # replace with your value
TGT_ID=$(boundary targets create ssh -scope-id "$PROJ_ID" \
  -name node-ssh -description "SSH to EKS dev nodes" \
  -default-port 22 \
  -address "$NODE_ADDRESS" \
  -egress-worker-filter '"dev" in "/tags/env"' \
  -format json | jq -r .item.id)

# Inject the key (as opposed to brokering it to the client), so the operator
# never handles the private key.
boundary targets add-credential-sources -id "$TGT_ID" \
  -injected-application-credential-source "$CL_ID"
```

## Part C - RBAC and connect

```bash
# Grant authorize-session on the target to a group of operators.
ROLE_ID=$(boundary roles create -scope-id "$PROJ_ID" \
  -name eks-dev-ssh -grant-scope-id "$PROJ_ID" \
  -format json | jq -r .item.id)

boundary roles add-grants -id "$ROLE_ID" \
  -grant "ids=$TGT_ID;actions=authorize-session"

boundary roles add-principals -id "$ROLE_ID" -principal <group-id>

# Connect. The key is injected automatically - no key or password prompt.
boundary connect ssh -target-id "$TGT_ID"
```

## Repeating for staging and prod

Each environment gets its **own** credential store and token. Swap four things
and re-run Parts A-C:

| Change | dev | staging | prod |
| --- | --- | --- | --- |
| Project scope | `eks-dev` | `eks-staging` | `eks-prod` |
| KV path | `secret/boundary/eks-dev/...` | `secret/boundary/eks-staging/...` | `secret/boundary/eks-prod/...` |
| Read policy | `boundary-eks-dev-read` | `boundary-eks-staging-read` | `boundary-eks-prod-read` |
| Egress filter / worker `env` tag | `dev` | `staging` | `prod` |

## Gotchas

- **KV v2 path needs `data/`.** The CLI writes to `secret/boundary/...` but the
  Boundary `-vault-path` must be `secret/data/boundary/...`.
- **Token requirements.** The Vault token must be **periodic, orphan, and
  renewable**, or Boundary cannot keep it alive and the store breaks.
- **Injection vs brokering.** `-injected-application-credential-source` injects
  the key into the session (operator never sees it) and requires the `ssh` target
  type plus HCP Boundary. Use `-brokered-credential-source` only if you want the
  client to receive the credential.
- **Worker reachability and tags.** The egress filter must match a worker tag,
  and that worker must have a network path to the SSH host on port 22.
- **Namespace.** HCP Vault operates under `admin`; use your working namespace
  `admin/hcp-platform` for both the secrets and the credential store.

## Production note: dynamic hosts

The example targets a single `-address`. For real EKS nodes (which come and go),
replace the static address with an **AWS dynamic host catalog** (the host plugin)
so Boundary discovers node IPs by tag automatically, and attach a host set to the
target instead of a fixed address.

## Appendix A: Creating the SSH key pair

`eks-dev-node-ssh.pem` is an EC2 SSH key pair. Its **public** half must be on the
nodes; its **private** half is what you store in Vault (Part A, step 1).

Option A (recommended) - generate locally, import only the public key to AWS:

```bash
ssh-keygen -t ed25519 -N "" -C "eks-dev-node" -f eks-dev-node-ssh.pem
chmod 400 eks-dev-node-ssh.pem
aws ec2 import-key-pair --key-name eks-dev-node \
  --public-key-material fileb://eks-dev-node-ssh.pem.pub --region eu-central-1
```

Option B - let AWS generate the pair:

```bash
aws ec2 create-key-pair --key-name eks-dev-node --key-type ed25519 \
  --query KeyMaterial --output text --region eu-central-1 > eks-dev-node-ssh.pem
chmod 400 eks-dev-node-ssh.pem
```

Put the public key on the nodes by attaching the key pair to the managed node
group (`terraform-aws-modules/eks`):

```hcl
eks_managed_node_groups = {
  one = {
    # ...
    remote_access = {
      ec2_ssh_key = "eks-dev-node"   # the key-pair NAME
    }
  }
}
```

After storing the private key in Vault (Part A), shred the local copy:
`shred -u eks-dev-node-ssh.pem`. Never commit it (`*.pem` is gitignored).

## Appendix B: Automating it with Terraform

The key pair, the Vault write, the Boundary store/library/target, **and the
in-cluster worker** are all generated on `terraform apply` via
[`infra/aws-eks/boundary-ssh.tf`](../infra/aws-eks/boundary-ssh.tf), gated behind
`enable_boundary_ssh`. It uses `tls_private_key` + `aws_key_pair`, writes the key
with `vault_kv_secret_v2`, creates the Boundary store/library/target, and deploys
the worker with a `boundary_worker` (controller-led) + `helm_release` tagged
`env = [var.environment]`.

Prerequisites for the automated path:

- The run's Vault token (the HCP Terraform dynamic-credentials role) must have
  **write** on `secret/data/boundary/eks-<env>/*` - the default `tfc-read` role
  is read-only, so add a write policy.
- Boundary admin credentials and an existing project scope (`boundary_project_id`),
  plus the periodic credential-store token from Part A.4.
- `hcp_boundary_cluster_id` so the worker can register with HCP Boundary.

Note: the worker Helm release deploys into the same cluster this config builds,
so on a from-scratch apply the cluster must exist first (target the cluster, or
let an existing cluster be in place).

Note: the generated private key is held in Terraform state (sensitive). Keep
state in HCP Terraform (encrypted), as this project does.
