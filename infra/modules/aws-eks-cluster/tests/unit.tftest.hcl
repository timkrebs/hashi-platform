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
