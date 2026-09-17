# Unit tests: plan mode with mocked providers; the AMI and partition lookups are
# replaced by fixed values. No AWS credentials needed.
#
#   cd infra/modules/aws-checkmk-server && terraform init -backend=false && terraform test

mock_provider "aws" {}
mock_provider "random" {}

override_data {
  target = data.aws_ami.hardened[0]
  values = {
    id = "ami-0123456789abcdef0"
  }
}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

# The parameter ARN is embedded in the instance role policy. Overriding it
# during the plan is what makes that policy inspectable below.
override_resource {
  target          = aws_ssm_parameter.admin_password
  override_during = plan
  values = {
    arn = "arn:aws:ssm:us-east-1:123456789012:parameter/unit-test-checkmk/cmkadmin-password"
  }
}

# Likewise the elastic IP, which the url output is built from.
override_resource {
  target          = aws_eip.this
  override_during = plan
  values = {
    public_ip = "203.0.113.10"
  }
}

variables {
  name      = "unit-test-checkmk"
  region    = "us-east-1"
  vpc_id    = "vpc-0123456789abcdef0"
  subnet_id = "subnet-0123456789abcdef0"

  tags = {
    Environment = "Dev"
    Project     = "hashi-platform"
    ManagedBy   = "Terraform"
  }
}

run "defaults_produce_a_hardened_public_instance" {
  command = plan

  assert {
    condition     = aws_instance.this.instance_type == "t3.medium" && aws_instance.this.subnet_id == "subnet-0123456789abcdef0"
    error_message = "Instance should use the default type and the supplied subnet."
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0123456789abcdef0"
    error_message = "Instance should launch from the looked-up Ubuntu 24.04 AMI."
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required" && aws_instance.this.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Instance metadata should require IMDSv2 and not be reachable from containers."
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true && aws_instance.this.root_block_device[0].volume_type == "gp3" && aws_instance.this.root_block_device[0].volume_size == 30
    error_message = "Root volume should be an encrypted 30 GiB gp3 volume."
  }

  assert {
    condition     = aws_instance.this.associate_public_ip_address == true && aws_instance.this.user_data_replace_on_change == true
    error_message = "Instance should get a public address and be replaced when the bootstrap changes."
  }
}

# The module never sets key_name, so shell access can only be Session Manager.
# key_name itself is unknowable during a plan, so the guard is the absence of
# an SSH port and the presence of the managed policy asserted further down.
run "no_port_22_is_ever_opened" {
  command = plan

  assert {
    condition     = alltrue([for rule in values(aws_vpc_security_group_ingress_rule.this) : rule.to_port != 22 && rule.from_port != 22])
    error_message = "Port 22 should never be opened."
  }
}

run "web_ports_are_open_to_the_allowed_cidrs" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 2
    error_message = "Defaults should open exactly two ports to one CIDR block."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["443-0.0.0.0/0"].to_port == 443 && aws_vpc_security_group_ingress_rule.this["443-0.0.0.0/0"].ip_protocol == "tcp" && aws_vpc_security_group_ingress_rule.this["443-0.0.0.0/0"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "The interface should be reachable on 443 from the allowed CIDR."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["80-0.0.0.0/0"].to_port == 80
    error_message = "Port 80 should be open so it can redirect to 443."
  }
}

run "custom_cidrs_produce_one_rule_per_port_and_block" {
  command = plan

  variables {
    allowed_cidr_blocks = ["203.0.113.0/24", "198.51.100.7/32"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 4
    error_message = "Two ports across two CIDR blocks should produce four ingress rules."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["443-198.51.100.7/32"].cidr_ipv4 == "198.51.100.7/32"
    error_message = "Each allowed CIDR should get its own rule."
  }
}

# Mirrors the hard-mandatory require-mandatory-tags Sentinel policy. Missing
# tags on any one of these blocks the apply with no override.
run "every_taggable_resource_carries_the_mandatory_tags" {
  command = plan

  assert {
    condition = alltrue([
      for tagset in concat(
        [
          aws_instance.this.tags,
          aws_instance.this.root_block_device[0].tags,
          aws_security_group.this.tags,
          aws_eip.this.tags,
          aws_ssm_parameter.admin_password.tags,
          aws_iam_role.this.tags,
          aws_iam_instance_profile.this.tags,
          aws_vpc_security_group_egress_rule.this.tags,
        ],
        [for rule in values(aws_vpc_security_group_ingress_rule.this) : rule.tags],
      ) : alltrue([for key in ["Environment", "Project", "ManagedBy"] : contains(keys(tagset), key)])
    ])
    error_message = "Every taggable resource must carry Environment, Project and ManagedBy."
  }

  assert {
    condition     = aws_instance.this.tags["Name"] == "unit-test-checkmk"
    error_message = "Resources should carry a Name tag derived from the module name."
  }
}

run "user_data_pins_the_checksum_and_names_the_parameter" {
  command = plan

  assert {
    condition     = strcontains(base64decode(aws_instance.this.user_data_base64), var.package_sha256)
    error_message = "The bootstrap must verify the package against the pinned checksum."
  }

  assert {
    condition     = strcontains(base64decode(aws_instance.this.user_data_base64), aws_ssm_parameter.admin_password.name)
    error_message = "The bootstrap must read the password from the SSM parameter this module creates."
  }

  assert {
    condition     = strcontains(base64decode(aws_instance.this.user_data_base64), "omd create --admin-password")
    error_message = "The bootstrap must set the admin password non-interactively."
  }

  assert {
    condition     = strcontains(base64decode(aws_instance.this.user_data_base64), "X-Forwarded-Proto")
    error_message = "Apache must forward the scheme, or login redirects loop forever."
  }
}

# The core security invariant. The strong guarantee is structural rather than a
# string comparison: random_password.admin.result is not known until apply, so
# if it were interpolated into the script then user_data_base64 would be unknown
# during the plan and every assertion here that decodes it would fail outright.
# These two pin the mechanism that keeps it that way.
run "the_password_is_fetched_at_boot_not_baked_in" {
  command = plan

  assert {
    condition     = strcontains(base64decode(aws_instance.this.user_data_base64), "CMK_PASSWORD=\"$(read_password")
    error_message = "The password must be read at boot, never interpolated into the script."
  }

  assert {
    condition     = strcontains(base64decode(aws_instance.this.user_data_base64), "get_parameter(Name=name, WithDecryption=True)")
    error_message = "The bootstrap must read the password from SSM Parameter Store."
  }
}

run "password_is_stored_encrypted" {
  command = plan

  assert {
    condition     = aws_ssm_parameter.admin_password.type == "SecureString"
    error_message = "The admin password must be stored as a SecureString."
  }
}

run "iam_grants_are_scoped_to_the_password_parameter" {
  command = plan

  assert {
    condition     = join(",", jsondecode(aws_iam_role_policy.admin_password.policy).Statement[0].Action) == "ssm:GetParameter"
    error_message = "The role should be able to read one parameter, not call SSM broadly."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.admin_password.policy).Statement[1].Condition.StringEquals["kms:ViaService"] == "ssm.us-east-1.amazonaws.com"
    error_message = "kms:Decrypt should be usable only through SSM in this region."
  }

  assert {
    condition     = endswith(aws_iam_role_policy_attachment.ssm_core.policy_arn, "AmazonSSMManagedInstanceCore")
    error_message = "Session Manager access should come from the AWS managed policy."
  }
}

run "url_points_at_the_site_over_https" {
  command = plan

  assert {
    condition     = startswith(output.url, "https://") && endswith(output.url, "/cmk/")
    error_message = "The URL should address the site over HTTPS."
  }
}

run "pinned_ami_skips_the_lookup" {
  command = plan

  variables {
    ami_id = "ami-0fedcba987654321f"
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0fedcba987654321f" && length(data.aws_ami.hardened) == 0
    error_message = "A pinned ami_id should be used and the lookup skipped."
  }
}

run "rejects_instance_types_larger_than_medium" {
  command = plan

  variables {
    instance_type = "t3.large"
  }

  expect_failures = [var.instance_type]
}

run "rejects_malformed_instance_type" {
  command = plan

  variables {
    instance_type = "t3medium"
  }

  expect_failures = [var.instance_type]
}

run "rejects_empty_allowed_cidr_blocks" {
  command = plan

  variables {
    allowed_cidr_blocks = []
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "rejects_invalid_cidr_block" {
  command = plan

  variables {
    allowed_cidr_blocks = ["10.0.0.0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "rejects_package_built_for_another_release" {
  command = plan

  variables {
    package_url = "https://download.checkmk.com/checkmk/2.4.0p36/check-mk-raw-2.4.0p36_0.jammy_amd64.deb"
  }

  expect_failures = [var.package_url]
}

run "rejects_plain_http_package_url" {
  command = plan

  variables {
    package_url = "http://download.checkmk.com/checkmk/2.4.0p36/check-mk-raw-2.4.0p36_0.noble_amd64.deb"
  }

  expect_failures = [var.package_url]
}

run "rejects_short_checksum" {
  command = plan

  variables {
    package_sha256 = "deadbeef"
  }

  expect_failures = [var.package_sha256]
}

run "rejects_invalid_site_name" {
  command = plan

  variables {
    site_name = "Check MK"
  }

  expect_failures = [var.site_name]
}

run "rejects_undersized_root_volume" {
  command = plan

  variables {
    root_volume_size = 8
  }

  expect_failures = [var.root_volume_size]
}

run "rejects_invalid_subnet_id" {
  command = plan

  variables {
    subnet_id = "vpc-0123456789abcdef0"
  }

  expect_failures = [var.subnet_id]
}

run "rejects_an_eks_image_family" {
  command = plan

  variables {
    ami_name_prefix = "hc-base-ubuntu-2404-eks-1.35-amd64"
  }

  expect_failures = [var.ami_name_prefix]
}

run "rejects_an_image_family_that_is_not_noble" {
  command = plan

  variables {
    ami_name_prefix = "hc-base-ubuntu-2604-amd64"
  }

  expect_failures = [var.ami_name_prefix]
}

run "rejects_a_malformed_ami_owner" {
  command = plan

  variables {
    ami_owner = "ami-prod"
  }

  expect_failures = [var.ami_owner]
}
