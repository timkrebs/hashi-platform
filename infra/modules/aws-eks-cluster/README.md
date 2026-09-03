# aws-eks-cluster

Creates an EKS cluster with managed node groups in an existing VPC, plus the
IAM role (IRSA) and add-on registration for the EBS CSI driver so that
persistent volumes work out of the box.

The module wraps
[terraform-aws-modules/eks/aws](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/20.8.5)
and
[terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc](https://registry.terraform.io/modules/terraform-aws-modules/iam/aws/5.39.0/submodules/iam-assumable-role-with-oidc)
behind a small, typed interface. The network is deliberately not part of this
module: VPCs are usually shared and outlive clusters, so pair it with
[`aws-vpc`](../aws-vpc) or bring your own subnets.

Defaults worth knowing:

- Node groups use Amazon Linux 2023 images. Amazon Linux 2 images are not
  published for Kubernetes 1.33 and later.
- The identity that runs Terraform is granted cluster-admin through an EKS
  access entry (`enable_cluster_creator_admin_permissions`).
- IAM roles get deterministic names (`<cluster>-cluster`, `<cluster>-<group>-node`,
  `<cluster>-ebs-csi`), which is why `cluster_name` is limited to 40 characters.

## Usage

```hcl
module "eks" {
  source = "../../modules/aws-eks-cluster"

  cluster_name    = "hashi-platform-dev-cluster"
  cluster_version = "1.33"

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
    spot = {
      instance_types = ["t3.large", "t3a.large"]
      min_size       = 0
      max_size       = 4
      desired_size   = 1
      capacity_type  = "SPOT"
      labels         = { lifecycle = "spot" }
      taints = {
        spot = { key = "lifecycle", value = "spot", effect = "NO_SCHEDULE" }
      }
    }
  }

  cluster_addons = {
    coredns = {}
    vpc-cni = {}
  }

  tags = {
    Environment = "Dev"
    Project     = "hashi-platform"
  }
}
```

After `apply`, connect with:

```sh
aws eks update-kubeconfig --region <region> --name <cluster_name>
```

## Requirements

| Name      | Version            |
|-----------|--------------------|
| terraform | >= 1.9.0           |
| aws       | >= 5.47.0, < 6.0.0 |

The upstream EKS module also needs the `tls`, `time`, `cloudinit` and `null`
providers; Terraform resolves them automatically.

## Inputs

| Name                                     | Description                                                                                       | Type                 | Default                                                              | Required |
|------------------------------------------|---------------------------------------------------------------------------------------------------|----------------------|----------------------------------------------------------------------|:--------:|
| cluster_name                             | Name of the cluster and prefix for IAM roles (1-40 chars)                                        | `string`             | n/a                                                                  | yes      |
| vpc_id                                   | VPC the cluster is created in                                                                     | `string`             | n/a                                                                  | yes      |
| subnet_ids                               | Subnets for control plane ENIs and node groups; at least two, preferably private                 | `list(string)`       | n/a                                                                  | yes      |
| cluster_version                          | Kubernetes minor version, for example `"1.33"`                                                    | `string`             | `"1.33"`                                                             | no       |
| cluster_endpoint_public_access           | Expose the API endpoint on the internet                                                           | `bool`               | `true`                                                               | no       |
| enable_cluster_creator_admin_permissions | Grant the Terraform identity cluster-admin via an access entry                                   | `bool`               | `true`                                                               | no       |
| ami_type                                 | AMI family for all node groups                                                                    | `string`             | `"AL2023_x86_64_STANDARD"`                                           | no       |
| node_groups                              | Managed node groups keyed by short name (see schema below)                                       | `map(object({...}))` | one `default` group: `t3.medium`, min 1, max 3, desired 2            | no       |
| cluster_addons                           | Additional add-ons keyed by name; `aws-ebs-csi-driver` is always managed by the module           | `map(object({...}))` | `{}`                                                                 | no       |
| tags                                     | Tags applied to every resource                                                                    | `map(string)`        | `{}`                                                                 | no       |

### `node_groups` schema

| Attribute      | Type                                                                | Default       | Notes                                              |
|----------------|---------------------------------------------------------------------|---------------|----------------------------------------------------|
| instance_types | `list(string)`                                                      | required      | At least one type                                  |
| min_size       | `number`                                                            | required      | `0 <= min_size <= desired_size <= max_size`        |
| max_size       | `number`                                                            | required      |                                                    |
| desired_size   | `number`                                                            | required      |                                                    |
| capacity_type  | `string`                                                            | `"ON_DEMAND"` | `ON_DEMAND` or `SPOT`                              |
| labels         | `map(string)`                                                       | `{}`          | Kubernetes node labels                             |
| taints         | `map(object({ key = string, value = optional(string), effect = string }))` | `{}`   | Effect: `NO_SCHEDULE`, `NO_EXECUTE`, `PREFER_NO_SCHEDULE` |

Keys must be 1-18 lowercase alphanumeric characters or hyphens.

### `cluster_addons` schema

| Attribute            | Type     | Default | Notes                                              |
|----------------------|----------|---------|----------------------------------------------------|
| addon_version        | `string` | latest  | Pin a specific add-on version                      |
| most_recent          | `bool`   | `true`  | Resolve the newest version compatible with the cluster |
| configuration_values | `string` | `null`  | JSON configuration passed to the add-on            |

## Outputs

| Name                               | Description                                                     |
|------------------------------------|-----------------------------------------------------------------|
| cluster_name                       | Name of the cluster                                             |
| cluster_arn                        | ARN of the cluster                                              |
| cluster_endpoint                   | URL of the Kubernetes API server                                |
| cluster_version                    | Kubernetes version of the control plane                         |
| cluster_certificate_authority_data | Base64 CA data for kubeconfig                                   |
| cluster_security_group_id          | Security group on the control plane ENIs                        |
| node_security_group_id             | Security group shared by the managed node groups                |
| oidc_provider                      | OIDC issuer URL without `https://`, for IRSA trust policies     |
| oidc_provider_arn                  | ARN of the IAM OIDC provider                                    |
| ebs_csi_irsa_role_arn              | ARN of the role assumed by the EBS CSI driver                   |

## Tests

Unit tests run in plan mode with a mocked AWS provider and the upstream EKS
and IAM modules replaced by fixed outputs, so they need no AWS credentials:

```sh
terraform init -backend=false
terraform test
```
