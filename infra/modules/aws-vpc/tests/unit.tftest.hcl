# Unit tests: run in plan mode against a mocked AWS provider, with the upstream
# VPC module replaced by fixed outputs. They exercise the subnet layout logic,
# the input validations and the output wiring without touching AWS.
#
#   cd infra/modules/aws-vpc && terraform init -backend=false && terraform test

mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
  }
}

override_module {
  target = module.vpc
  outputs = {
    vpc_id          = "vpc-0123456789abcdef0"
    vpc_cidr_block  = "10.0.0.0/16"
    private_subnets = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
    public_subnets  = ["subnet-public-a", "subnet-public-b", "subnet-public-c"]
    nat_public_ips  = ["203.0.113.10"]
  }
}

variables {
  name = "unit-test"
}

run "defaults_produce_three_zone_layout" {
  command = plan

  assert {
    condition     = output.availability_zones == tolist(["us-east-1a", "us-east-1b", "us-east-1c"])
    error_message = "Expected the first three available zones to be selected, got ${jsonencode(output.availability_zones)}."
  }

  assert {
    condition     = output.private_subnet_cidrs == tolist(["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"])
    error_message = "Unexpected private subnet layout: ${jsonencode(output.private_subnet_cidrs)}."
  }

  assert {
    condition     = output.public_subnet_cidrs == tolist(["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24"])
    error_message = "Unexpected public subnet layout: ${jsonencode(output.public_subnet_cidrs)}."
  }

  assert {
    condition     = output.vpc_id == "vpc-0123456789abcdef0" && length(output.private_subnet_ids) == 3
    error_message = "Outputs are not wired to the upstream VPC module."
  }
}

run "custom_cidr_and_zone_count" {
  command = plan

  variables {
    cidr_block           = "10.42.0.0/16"
    az_count             = 2
    subnet_prefix_length = 20
  }

  assert {
    condition     = output.availability_zones == tolist(["us-east-1a", "us-east-1b"])
    error_message = "Expected two zones, got ${jsonencode(output.availability_zones)}."
  }

  assert {
    condition     = output.private_subnet_cidrs == tolist(["10.42.0.0/20", "10.42.16.0/20"])
    error_message = "Unexpected private subnet layout: ${jsonencode(output.private_subnet_cidrs)}."
  }

  assert {
    condition     = output.public_subnet_cidrs == tolist(["10.42.32.0/20", "10.42.48.0/20"])
    error_message = "Unexpected public subnet layout: ${jsonencode(output.public_subnet_cidrs)}."
  }
}

run "rejects_invalid_cidr" {
  command = plan

  variables {
    cidr_block = "not-a-cidr"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_vpc_prefix_outside_aws_limits" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/8"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_single_zone" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}

run "rejects_subnets_larger_than_vpc" {
  command = plan

  variables {
    cidr_block           = "10.0.0.0/24"
    subnet_prefix_length = 24
  }

  expect_failures = [var.subnet_prefix_length]
}

run "rejects_vpc_too_small_for_layout" {
  command = plan

  variables {
    cidr_block           = "10.0.0.0/26"
    subnet_prefix_length = 28
    az_count             = 3
  }

  expect_failures = [var.subnet_prefix_length]
}

run "fails_when_region_has_too_few_zones" {
  command = plan

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-west-1a", "us-west-1b"]
    }
  }

  expect_failures = [output.availability_zones]
}
