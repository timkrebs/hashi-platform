# cert-manager

Installs [cert-manager](https://cert-manager.io/) with its CRDs into its own
namespace. The platform uses it to issue Vault's self-signed CA and server
certificate; issuers and certificates themselves are declared next to the
workloads under `gitops/`, not here.

By default the CRDs are removed together with the release, so an ephemeral
environment leaves nothing behind. Set `keep_crds_on_uninstall = true` where
certificates must survive a reinstall.

## Usage

```hcl
module "cert_manager" {
  source = "../../../modules/cert-manager"
}
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

| Name                   | Description                                        | Type     | Default          | Required |
|------------------------|----------------------------------------------------|----------|------------------|:--------:|
| chart_version          | jetstack/cert-manager chart version                | `string` | `"1.21.1"`       | no       |
| namespace              | Namespace created for cert-manager                 | `string` | `"cert-manager"` | no       |
| keep_crds_on_uninstall | Keep CRDs (and all certificates) on uninstall      | `bool`   | `false`          | no       |

## Outputs

| Name          | Description                    |
|---------------|--------------------------------|
| namespace     | Namespace cert-manager runs in |
| release_name  | Helm release name              |
| chart_version | Installed chart version        |

## Tests

```sh
terraform init -backend=false
terraform test
```
