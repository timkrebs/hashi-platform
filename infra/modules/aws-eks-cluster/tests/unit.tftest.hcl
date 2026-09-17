# Unit tests: run in plan mode against a mocked AWS provider, with the upstream
# EKS and IAM modules replaced by fixed outputs. They exercise the node group
# transformation, the input validations and the output wiring without touching
# AWS.
#
#   cd infra/modules/aws-eks-cluster && terraform init -backend=false && terraform test

mock_provider "aws" {}

# The real provider still validates ARNs, so the partition must look genuine.
override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "unit-test"
    cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/unit-test"
    cluster_endpoint                   = "https://0123456789ABCDEF.gr7.us-east-1.eks.amazonaws.com"
    cluster_version                    = "1.33"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
    cluster_security_group_id          = "sg-0123456789abcdef0"
    node_security_group_id             = "sg-0fedcba9876543210"
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF"
  }
}

override_module {
  target = module.ebs_csi_irsa
  outputs = {
    iam_role_arn = "arn:aws:iam::123456789012:role/unit-test-ebs-csi"
  }
}

variables {
  cluster_name = "unit-test"
  vpc_id       = "vpc-0123456789abcdef0"
  subnet_ids   = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
}

run "outputs_are_wired_to_upstream_modules" {
  command = plan

  assert {
    condition     = output.cluster_name == "unit-test" && output.cluster_version == "1.33"
    error_message = "Cluster outputs are not passed through from the EKS module."
  }

  assert {
    condition     = output.cluster_endpoint == "https://0123456789ABCDEF.gr7.us-east-1.eks.amazonaws.com"
    error_message = "cluster_endpoint is not passed through from the EKS module."
  }

  assert {
    condition     = output.oidc_provider == "oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF"
    error_message = "oidc_provider is not passed through from the EKS module."
  }

  assert {
    condition     = output.ebs_csi_irsa_role_arn == "arn:aws:iam::123456789012:role/unit-test-ebs-csi"
    error_message = "ebs_csi_irsa_role_arn is not passed through from the IRSA module."
  }
}

run "default_node_group_is_derived_from_inputs" {
  command = plan

  assert {
    condition     = tolist(keys(local.node_groups)) == tolist(["default"])
    error_message = "Expected a single node group named default, got ${jsonencode(keys(local.node_groups))}."
  }

  assert {
    condition     = tolist(local.node_groups["default"].instance_types) == tolist(["t3.medium"]) && local.node_groups["default"].desired_size == 2
    error_message = "Default node group sizing does not match the variable default."
  }

  assert {
    condition     = local.node_groups["default"].capacity_type == "ON_DEMAND"
    error_message = "capacity_type should default to ON_DEMAND."
  }

  assert {
    condition     = local.node_groups["default"].iam_role_name == "unit-test-default-node" && local.node_groups["default"].iam_role_use_name_prefix == false
    error_message = "Node group IAM role name should be deterministic and derived from the cluster name."
  }
}

run "custom_node_groups_keep_labels_and_taints" {
  command = plan

  variables {
    node_groups = {
      general = {
        instance_types = ["m6i.large", "m5.large"]
        min_size       = 2
        max_size       = 6
        desired_size   = 3
        labels         = { workload = "general" }
      }
      spot = {
        instance_types = ["t3.large"]
        min_size       = 0
        max_size       = 4
        desired_size   = 1
        capacity_type  = "SPOT"
        taints = {
          spot = {
            key    = "spot"
            value  = "true"
            effect = "NO_SCHEDULE"
          }
        }
      }
    }
  }

  assert {
    condition     = tolist(sort(keys(local.node_groups))) == tolist(["general", "spot"])
    error_message = "Both node groups should be present."
  }

  assert {
    condition     = local.node_groups["general"].labels == tomap({ workload = "general" }) && length(local.node_groups["general"].taints) == 0
    error_message = "Labels or taints were not carried over for the general node group."
  }

  assert {
    condition     = local.node_groups["spot"].capacity_type == "SPOT" && local.node_groups["spot"].taints["spot"].effect == "NO_SCHEDULE"
    error_message = "Capacity type or taints were not carried over for the spot node group."
  }
}

run "rejects_invalid_cluster_version" {
  command = plan

  variables {
    cluster_version = "v1.33.1"
  }

  expect_failures = [var.cluster_version]
}

run "rejects_overlong_cluster_name" {
  command = plan

  variables {
    cluster_name = "this-cluster-name-is-far-too-long-for-iam-role-names"
  }

  expect_failures = [var.cluster_name]
}

run "rejects_malformed_vpc_id" {
  command = plan

  variables {
    vpc_id = "not-a-vpc"
  }

  expect_failures = [var.vpc_id]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-only-one"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_unknown_ami_type" {
  command = plan

  variables {
    ami_type = "WINDOWS_CORE_2022_x86_64"
  }

  expect_failures = [var.ami_type]
}

run "rejects_inconsistent_node_group_sizes" {
  command = plan

  variables {
    node_groups = {
      default = {
        instance_types = ["t3.medium"]
        min_size       = 3
        max_size       = 2
        desired_size   = 1
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "rejects_invalid_taint_effect" {
  command = plan

  variables {
    node_groups = {
      default = {
        instance_types = ["t3.medium"]
        min_size       = 1
        max_size       = 2
        desired_size   = 1
        taints = {
          bad = {
            key    = "bad"
            effect = "NoSchedule"
          }
        }
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "rejects_overriding_managed_addon" {
  command = plan

  variables {
    cluster_addons = {
      aws-ebs-csi-driver = {}
    }
  }

  expect_failures = [var.cluster_addons]
}

run "rejects_kms_deletion_window_outside_aws_range" {
  command = plan

  variables {
    kms_key_deletion_window_in_days = 3
  }

  expect_failures = [var.kms_key_deletion_window_in_days]
}

# The AWS-optimised image stays the default, so existing clusters are untouched
# until the hardened image is opted into explicitly.
run "aws_optimised_image_is_the_default" {
  command = plan

  assert {
    condition     = local.node_group_ami_defaults.ami_type == "AL2023_x86_64_STANDARD" && local.node_group_ami_defaults.ami_id == ""
    error_message = "Node groups should use the AWS-optimised AL2023 image by default."
  }

  assert {
    condition     = local.node_group_ami_defaults.enable_bootstrap_user_data == false
    error_message = "EKS injects the bootstrap itself for its own images."
  }

  assert {
    condition     = length(data.aws_ami.hardened_node) == 0 && output.node_ami_id == null
    error_message = "The hardened image should not be looked up unless it is asked for."
  }
}

# A custom AMI is not EKS-optimised, so the node group must be told the type is
# CUSTOM and the module must render the bootstrap into user data. Without both,
# nodes launch and never join the cluster.
run "hardened_image_switches_the_node_group_to_custom" {
  command = plan

  variables {
    use_hardened_node_ami = true
    cluster_version       = "1.35"
  }

  # Upstream nulls the node group's ami_type once ami_id is set, so a non-empty
  # ami_id is what actually puts the node group on the custom image.
  assert {
    condition     = local.node_group_ami_defaults.ami_id != "" && local.node_group_ami_defaults.ami_id != null
    error_message = "The hardened image should be passed to the node group as a custom AMI."
  }

  assert {
    condition     = local.node_group_ami_defaults.enable_bootstrap_user_data == true
    error_message = "EKS does not inject bootstrap user data for custom images; the module must render it."
  }

  assert {
    condition     = local.node_group_ami_defaults.platform == "linux"
    error_message = "The hardened image is Ubuntu, so the linux bootstrap template applies."
  }
}

# The image name carries its Kubernetes version, so deriving it from
# cluster_version is what stops the node image drifting ahead of the control
# plane, which Kubernetes forbids.
run "hardened_image_is_selected_by_cluster_version" {
  command = plan

  variables {
    use_hardened_node_ami = true
    cluster_version       = "1.35"
  }

  assert {
    condition     = anytrue([for f in one(data.aws_ami.hardened_node[*].filter) : contains(f.values, "hc-base-ubuntu-2404-eks-1.35-amd64-*")])
    error_message = "The image family must be derived from cluster_version and the architecture."
  }
}

run "hardened_image_honours_the_architecture" {
  command = plan

  variables {
    use_hardened_node_ami = true
    cluster_version       = "1.35"
    node_ami_architecture = "arm64"
  }

  assert {
    condition     = anytrue([for f in one(data.aws_ami.hardened_node[*].filter) : contains(f.values, "hc-base-ubuntu-2404-eks-1.35-arm64-*")])
    error_message = "The architecture should select the matching hardened image."
  }
}

run "rejects_an_unknown_node_ami_architecture" {
  command = plan

  variables {
    use_hardened_node_ami = true
    node_ami_architecture = "x86_64"
  }

  expect_failures = [var.node_ami_architecture]
}

run "rejects_a_malformed_node_ami_owner" {
  command = plan

  variables {
    node_ami_owner = "ami-prod"
  }

  expect_failures = [var.node_ami_owner]
}
