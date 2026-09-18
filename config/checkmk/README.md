# Checkmk configuration

Everything on the cluster side is declarative — the collectors in `gitops/`, the
IAM and log group in `infra/`, the Vault AppRole in `config/vault/`. This
directory is the part that is not: **there is no Terraform provider for
Checkmk** (verified against the registry: `provider not found`), so the site's
own configuration is done through its REST API or the UI.

Checked against the running site: Checkmk **2.4.0p36**, edition **cre** (Raw),
site `cmk`. All four rulesets used below exist in that edition:

| Ruleset | Used for |
| --- | --- |
| `active_checks:httpv2` | Vault health, no token required |
| `special_agents:kube` | Kubernetes cluster, nodes, workloads |
| `special_agents:prometheus` | Vault telemetry, needs an AppRole token |
| `active_checks:cert` | Certificate expiry, optional |

## 1. Vault health

The cheapest useful check, and the one to add first. `/v1/sys/health` is
unauthenticated, so no credential is involved. It answers with a status code
that already encodes the state:

| Code | Meaning |
| --- | --- |
| 200 | initialised, unsealed, active |
| 429 | unsealed but standby — normal for two of the three pods |
| 501 | not initialised |
| 503 | sealed |

Create an `active_checks:httpv2` rule against
`https://<vault-nlb>:8200/v1/sys/health`, treat 200 and 429 as OK and 501/503 as
critical. The certificate is signed by the in-cluster CA, so either upload that
CA to the site or disable certificate validation on this check alone.

## 2. Kubernetes

`special_agents:kube` needs two endpoints and a token:

- **API server** — public on this cluster, take it from
  `aws eks describe-cluster --name hashi-platform-dev-cluster --query cluster.endpoint`
- **Cluster collector** — the internal load balancer created by
  `gitops/apps/checkmk-kube-agent.yaml`:
  ```sh
  kubectl get svc -n checkmk-monitoring \
    -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}'
  ```
  It is deliberately `internal`: the Checkmk host sits in the same VPC, and
  nothing outside it needs to read container metrics.
- **Token** — the service account the chart creates:
  ```sh
  kubectl create token checkmk -n checkmk-monitoring --duration=8760h
  ```

## 3. Vault telemetry

`special_agents:prometheus` scraping
`https://<vault-nlb>:8200/v1/sys/metrics?format=prometheus`.

The endpoint requires a token, and that is on purpose: the listener is published
through an internet-facing load balancer, so turning on
`unauthenticated_metrics_access` would put seal state, token counts and request
rates on the open internet. `config/vault/` therefore creates an AppRole with a
policy covering `sys/metrics` and `sys/health` and nothing else, bound to the
VPC CIDR so a leaked credential is useless from outside.

```sh
terraform -chdir=config/vault output -raw checkmk_approle_role_id
eval "$(terraform -chdir=config/vault output -raw checkmk_secret_id_command)"
```

The secret ID is created out of band rather than by Terraform, so a long-lived
credential never lands in state.

## What is deliberately not here

**Logs.** Checkmk alerts on patterns in a file an agent can read; it does not
store or search log history. Container logs go to CloudWatch instead, through
`gitops/apps/fluent-bit.yaml` and the `aws-fluent-bit-cloudwatch` module, with
the log group and its retention owned by Terraform. Searching logs happens in
CloudWatch, alerting on state happens in Checkmk.

**Node operating system metrics.** The Checkmk agent on the EKS nodes
themselves would add CPU, disk and systemd state per node. The container view
from the kube agent already covers most of it, so it is left out until there is
a reason.

## Capacity

The site runs on a `t3.medium` with 4 GB, which the `restrict-compute-size`
policy caps. That is fine for this cluster; if the number of monitored services
grows, a second Checkmk host is the way out rather than a bigger one.
