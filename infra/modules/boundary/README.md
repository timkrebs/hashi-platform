# boundary

Placeholder for the access layer: HCP Boundary as the control plane, with
self-managed workers running in each environment. Today the module can create
the HCP Boundary cluster and is **disabled by default**; it exists so the
layout, provider requirements and tests are in place before the rest lands.

## Intended design

| Piece | Where | Notes |
|---|---|---|
| Control plane | `hcp_boundary_cluster` (this module) | One cluster; `hcp` provider credentials come from HCP Terraform sensitive variables. |
| Workers | `gitops/apps/boundary-worker` (kustomize Deployment of `hashicorp/boundary`) | Controller-led registration: Terraform obtains the activation token from `boundary_worker` and writes it to a Kubernetes Secret from the platform root, never to an annotation. Workers get a public NLB restricted by CIDR, like Vault. |
| Targets | this module, `boundary_target` | EKS nodes over SSH (private IPs, host set from node security group membership) and the Vault API over TCP. |
| Credentials | this module, `boundary_credential_store_vault` | Brokered from Vault; needs a Vault token issued by the later `vault` configuration root. |
| Node SSH trust | `aws-eks-cluster` future input `ssh_ca_public_key` | Vault SSH CA public key written to `TrustedUserCAKeys` on AL2023 nodes through the launch template user data. |

The `boundary` provider is added when targets and credential stores are
implemented; until then only `hcp` is required.

## Usage

```hcl
module "boundary" {
  source = "../../../modules/boundary"

  enabled        = false
  cluster_id     = "hashi-platform-production"
  admin_password = var.boundary_admin_password # sensitive HCP Terraform variable
}
```

## Requirements

| Name      | Version             |
|-----------|---------------------|
| terraform | >= 1.9.0            |
| hcp       | >= 0.100.0, < 1.0.0 |

## Inputs

| Name           | Description                                        | Type     | Default      | Required |
|----------------|----------------------------------------------------|----------|--------------|:--------:|
| cluster_id     | ID of the HCP Boundary cluster (3-36 chars)        | `string` | n/a          | yes      |
| enabled        | Create the cluster                                 | `bool`   | `false`      | no       |
| tier           | `Standard` or `Plus`                               | `string` | `"Standard"` | no       |
| admin_username | Initial administrator login                        | `string` | `"admin"`    | no       |
| admin_password | Initial administrator password (sensitive)         | `string` | `null`       | no       |

## Outputs

| Name        | Description                                  |
|-------------|----------------------------------------------|
| enabled     | Whether the cluster is managed               |
| cluster_id  | Cluster ID                                   |
| cluster_url | Cluster URL, or null while disabled          |

## Tests

```sh
terraform init -backend=false
terraform test
```
