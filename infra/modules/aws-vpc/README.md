# aws-vpc

Creates an EKS-ready VPC: one private and one public subnet per availability
zone, an internet gateway, NAT gateway(s) for the private subnets, and the
`kubernetes.io/role/*` subnet tags that the AWS Load Balancer Controller uses
to discover subnets.

Subnets are derived from `cidr_block`, `az_count` and `subnet_prefix_length`,
so every environment gets the same layout without hand-maintained CIDR lists.
Local Zones and Wavelength Zones are skipped because managed node groups do
not support them.

The module is a thin, opinionated wrapper around
[terraform-aws-modules/vpc/aws](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/5.8.1).

## Usage

```hcl
module "network" {
  source = "../../modules/aws-vpc"

  name       = "hashi-platform-dev-cluster-vpc"
  cidr_block = "10.0.0.0/16"
  az_count   = 3

  single_nat_gateway = true # false for production

  tags = {
    Environment = "Dev"
    Project     = "hashi-platform"
  }
}
```

With the defaults above the layout is:

| Zone | Private subnet | Public subnet |
|------|----------------|---------------|
| 1    | 10.0.0.0/24    | 10.0.3.0/24   |
| 2    | 10.0.1.0/24    | 10.0.4.0/24   |
| 3    | 10.0.2.0/24    | 10.0.5.0/24   |

## Requirements

| Name      | Version            |
|-----------|--------------------|
| terraform | >= 1.9.0           |
| aws       | >= 5.47.0, < 6.0.0 |

## Inputs

| Name                 | Description                                                                 | Type          | Default         | Required |
|----------------------|-----------------------------------------------------------------------------|---------------|-----------------|:--------:|
| name                 | Name of the VPC and prefix for subnet, route table and NAT gateway names    | `string`      | n/a             | yes      |
| cidr_block           | IPv4 CIDR block for the VPC (/16 to /28)                                    | `string`      | `"10.0.0.0/16"` | no       |
| az_count             | Number of availability zones (2 to 6); one private and one public subnet each | `number`    | `3`             | no       |
| subnet_prefix_length | Prefix length of every subnet; must be larger than the VPC prefix, at most 28 | `number`    | `24`            | no       |
| enable_nat_gateway   | Create NAT gateways so private subnets can reach the internet               | `bool`        | `true`          | no       |
| single_nat_gateway   | Share one NAT gateway instead of one per zone (cheaper, not HA)             | `bool`        | `true`          | no       |
| tags                 | Tags applied to every resource                                              | `map(string)` | `{}`            | no       |

## Outputs

| Name                 | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| vpc_id               | ID of the VPC                                                      |
| vpc_cidr_block       | IPv4 CIDR block of the VPC                                         |
| availability_zones   | Zones used, in the same order as the subnet lists                  |
| private_subnet_ids   | Private subnet IDs, one per zone                                   |
| private_subnet_cidrs | Private subnet CIDR blocks, same order as `private_subnet_ids`     |
| public_subnet_ids    | Public subnet IDs, one per zone                                    |
| public_subnet_cidrs  | Public subnet CIDR blocks, same order as `public_subnet_ids`       |
| nat_public_ips       | Elastic IPs of the NAT gateways                                    |

## Tests

Unit tests run in plan mode with a mocked AWS provider and the upstream VPC
module replaced by fixed outputs, so they need no AWS credentials:

```sh
terraform init -backend=false
terraform test
```
