# Unit tests: plan mode with a mocked AWS provider and the upstream IRSA module
# replaced by fixed outputs. No AWS credentials needed.
#
#   cd infra/modules/aws-fluent-bit-cloudwatch && terraform init -backend=false && terraform test

mock_provider "aws" {}

override_module {
  target = module.irsa
  outputs = {
    iam_role_arn  = "arn:aws:iam::123456789012:role/unit-test-fluent-bit"
    iam_role_name = "unit-test-fluent-bit"
  }
}

# The policy document embeds the log group ARN, which a mocked provider only
# knows at apply time. Overriding it during the plan is what makes the policy
# inspectable below.
override_resource {
  target          = aws_cloudwatch_log_group.this
  override_during = plan
  values = {
    arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/eks/unit-test/containers"
  }
}

variables {
  cluster_name      = "unit-test"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF"

  tags = {
    Environment = "Dev"
    Project     = "hashi-platform"
    ManagedBy   = "Terraform"
  }
}

run "log_group_has_an_explicit_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 14
    error_message = "Logs must expire; an auto-created group keeps them forever and bills for it."
  }
}

# Without this the module would be free to create a second group with no
# retention whenever the output is misconfigured.
run "fluent_bit_cannot_create_log_groups" {
  command = plan

  assert {
    condition     = !strcontains(local.policy, "logs:CreateLogGroup")
    error_message = "Fluent Bit must not be able to create log groups of its own."
  }

  assert {
    condition = alltrue([
      for action in ["logs:CreateLogStream", "logs:PutLogEvents"] :
      strcontains(local.policy, action)
    ])
    error_message = "Fluent Bit must be able to write into the existing group."
  }
}

run "write_access_is_scoped_to_the_one_group" {
  command = plan

  assert {
    condition     = !strcontains(local.policy, "\"Resource\": \"*\"")
    error_message = "The policy must name its log group rather than every log group in the account."
  }
}

run "taggable_resources_carry_the_mandatory_tags" {
  command = plan

  assert {
    condition = alltrue([
      for tagset in [aws_cloudwatch_log_group.this.tags, aws_iam_policy.this.tags] :
      alltrue([for key in ["Environment", "Project", "ManagedBy"] : contains(keys(tagset), key)])
    ])
    error_message = "Every taggable resource must carry Environment, Project and ManagedBy."
  }
}

run "rejects_a_retention_cloudwatch_does_not_accept" {
  command = plan

  variables {
    retention_in_days = 10
  }

  expect_failures = [var.retention_in_days]
}
