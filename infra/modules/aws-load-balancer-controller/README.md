# aws-load-balancer-controller

Installs the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
with an IRSA role, so that Kubernetes `Service` objects of type `LoadBalancer`
and `Ingress` resources become NLBs and ALBs. It is part of the platform layer
because workloads managed by Argo CD (Vault's public endpoint, later Boundary
workers) rely on it, and because it must still be running when those
workloads are deleted during a teardown, or their load balancers leak.

The IAM policy comes from
[terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks](https://registry.terraform.io/modules/terraform-aws-modules/iam/aws/5.39.0/submodules/iam-role-for-service-accounts-eks),
so it stays in step with the controller version.

## Usage

```hcl
module "aws_load_balancer_controller" {
  source = "../../../modules/aws-load-balancer-controller"

  cluster_name      = "hashi-platform-dev-cluster"
  region            = "us-east-1"
  vpc_id            = data.terraform_remote_state.cluster.outputs.vpc_id
  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn

  tags = local.common_tags
}
```

The calling root must configure the `helm` provider against the cluster.

## Requirements

| Name      | Version            |
|-----------|--------------------|
| terraform | >= 1.9.0           |
| aws       | >= 5.47.0, < 6.0.0 |
| helm      | >= 3.0.0, < 4.0.0  |

## Inputs

| Name                 | Description                                                  | Type          | Default                          | Required |
|----------------------|--------------------------------------------------------------|---------------|----------------------------------|:--------:|
| cluster_name         | EKS cluster name (1-40 chars); prefixes the IAM role name     | `string`      | n/a                              | yes      |
| region               | AWS region of the cluster                                    | `string`      | n/a                              | yes      |
| vpc_id               | VPC the cluster runs in                                      | `string`      | n/a                              | yes      |
| oidc_provider_arn    | ARN of the cluster's IAM OIDC provider                       | `string`      | n/a                              | yes      |
| chart_version        | eks/aws-load-balancer-controller chart version               | `string`      | `"3.5.0"`                        | no       |
| namespace            | Namespace to install into (must exist)                       | `string`      | `"kube-system"`                  | no       |
| service_account_name | Controller service account bound to the IRSA role            | `string`      | `"aws-load-balancer-controller"` | no       |
| replica_count        | Controller replicas                                          | `number`      | `1`                              | no       |
| tags                 | Tags for the IAM resources                                   | `map(string)` | `{}`                             | no       |

## Outputs

| Name          | Description                                  |
|---------------|----------------------------------------------|
| iam_role_arn  | IAM role the controller assumes through IRSA |
| release_name  | Helm release name                            |
| namespace     | Namespace the controller runs in             |
| chart_version | Installed chart version                      |

## Tests

```sh
terraform init -backend=false
terraform test
```

Plan-mode unit tests with mocked `aws` and `helm` providers; the IRSA module
is replaced by fixed outputs.
