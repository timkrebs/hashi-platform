# argocd

Installs [Argo CD](https://argo-cd.readthedocs.io/) and registers the local
cluster explicitly. Argo CD treats the in-cluster destination as implicit,
but only a registration `Secret` can carry **labels** (so ApplicationSets can
select the cluster) and **annotations** (the bridge through which Terraform
hands account-specific values such as IAM role ARNs and the KMS alias to
GitOps manifests).

Defaults are deliberately small: no Dex, no notifications, the API server in
insecure mode for access through `kubectl port-forward`, resource requests
sized for `t3.medium` nodes, CRDs removed with the release. Anything else goes
through `additional_values`.

## Usage

```hcl
module "argocd" {
  source = "../../../modules/argocd"

  cluster_secret_labels = {
    "hashi-platform.io/environment" = "dev"
  }

  cluster_secret_annotations = {
    "hashi-platform.io/environment"         = "dev"
    "hashi-platform.io/vault-kms-key-alias" = module.vault_prerequisites.kms_key_alias
    "hashi-platform.io/vault-irsa-role-arn" = module.vault_prerequisites.vault_irsa_role_arn
  }
}
```

An ApplicationSet then selects the cluster with a cluster generator and reads
the values:

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          hashi-platform.io/environment: dev
template:
  spec:
    source:
      helm:
        parameters:
          - name: vault.server.extraEnvironmentVars.VAULT_AWSKMS_SEAL_KEY_ID
            value: '{{ index .metadata.annotations "hashi-platform.io/vault-kms-key-alias" }}'
```

The calling root must configure the `helm` and `kubernetes` providers against
the cluster.

## Requirements

| Name       | Version           |
|------------|-------------------|
| terraform  | >= 1.9.0          |
| helm       | >= 3.0.0, < 4.0.0 |
| kubernetes | >= 3.0.0, < 4.0.0 |

## Inputs

| Name                       | Description                                                       | Type           | Default    | Required |
|----------------------------|-------------------------------------------------------------------|----------------|------------|:--------:|
| chart_version              | argo/argo-cd chart version                                        | `string`       | `"10.7.1"` | no       |
| namespace                  | Namespace created for Argo CD                                     | `string`       | `"argocd"` | no       |
| server_insecure            | Serve API and UI over plain HTTP inside the cluster               | `bool`         | `true`     | no       |
| cluster_secret_labels      | Extra labels on the in-cluster registration secret                | `map(string)`  | `{}`       | no       |
| cluster_secret_annotations | Annotations on the in-cluster registration secret                 | `map(string)`  | `{}`       | no       |
| additional_values          | Extra Helm values documents merged after the defaults             | `list(string)` | `[]`       | no       |

## Outputs

| Name                           | Description                                      |
|--------------------------------|--------------------------------------------------|
| namespace                      | Namespace Argo CD runs in                        |
| release_name                   | Helm release name                                |
| chart_version                  | Installed chart version                          |
| cluster_secret_name            | Name of the in-cluster registration secret       |
| port_forward_command           | Command exposing the UI on http://localhost:8080 |
| initial_admin_password_command | Command printing the initial admin password      |

## Tests

```sh
terraform init -backend=false
terraform test
```
