# Unit tests: plan mode against a mocked AWS provider, with the upstream IRSA
# modules replaced by fixed outputs. No AWS access needed.
#
#   cd infra/modules/vault-aws-prerequisites && terraform init -backend=false && terraform test

mock_provider "aws" {}

# The real provider validates IAM policy JSON, so the mocked documents must
# render as valid policies.
override_data {
  target = data.aws_iam_policy_document.unseal
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.init
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_module {
  target = module.unseal_irsa
  outputs = {
    iam_role_arn = "arn:aws:iam::123456789012:role/unit-test-vault-unseal"
  }
}

override_module {
  target = module.init_irsa
  outputs = {
    iam_role_arn = "arn:aws:iam::123456789012:role/unit-test-vault-init"
  }
}

variables {
  name_prefix   = "unit-test"
  oidc_provider = "oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF"
}

run "derives_deterministic_names" {
  command = plan

  assert {
    condition     = aws_kms_alias.unseal.name == "alias/unit-test-vault-unseal"
    error_message = "KMS alias should be derived from name_prefix."
  }

  assert {
    condition     = aws_secretsmanager_secret.init.name == "unit-test/vault/init"
    error_message = "Init secret name should default to <name_prefix>/vault/init."
  }

  assert {
    condition     = aws_iam_policy.unseal.name == "unit-test-vault-unseal" && aws_iam_policy.init.name == "unit-test-vault-init"
    error_message = "IAM policy names should be derived from name_prefix."
  }

  assert {
    condition     = aws_kms_key.unseal.deletion_window_in_days == 30 && aws_kms_key.unseal.enable_key_rotation == true && aws_secretsmanager_secret.init.recovery_window_in_days == 30
    error_message = "Production-safe defaults expected: 30-day windows and key rotation on."
  }

  assert {
    condition     = output.vault_irsa_role_arn == "arn:aws:iam::123456789012:role/unit-test-vault-unseal" && output.vault_init_irsa_role_arn == "arn:aws:iam::123456789012:role/unit-test-vault-init"
    error_message = "IRSA role ARNs are not passed through."
  }
}

run "ephemeral_settings_and_custom_secret_name" {
  command = plan

  variables {
    init_secret_name                = "hashi-platform/dev/vault/init"
    kms_key_deletion_window_in_days = 7
    secret_recovery_window_in_days  = 0
  }

  assert {
    condition     = aws_secretsmanager_secret.init.name == "hashi-platform/dev/vault/init"
    error_message = "A custom init_secret_name should be used verbatim."
  }

  assert {
    condition     = aws_kms_key.unseal.deletion_window_in_days == 7 && aws_secretsmanager_secret.init.recovery_window_in_days == 0
    error_message = "Ephemeral windows should be applied."
  }
}

run "rejects_kms_window_outside_aws_range" {
  command = plan

  variables {
    kms_key_deletion_window_in_days = 3
  }

  expect_failures = [var.kms_key_deletion_window_in_days]
}

run "rejects_invalid_secret_recovery_window" {
  command = plan

  variables {
    secret_recovery_window_in_days = 5
  }

  expect_failures = [var.secret_recovery_window_in_days]
}

run "rejects_overlong_name_prefix" {
  command = plan

  variables {
    name_prefix = "this-prefix-is-much-too-long-to-keep-iam-role-names-legal"
  }

  expect_failures = [var.name_prefix]
}
