locals {
  init_secret_name = coalesce(var.init_secret_name, "${var.name_prefix}/vault/init")
}

# ---------------------------------------------------------------------------
# Auto-unseal key. Vault references it by alias, so the alias name is
# deterministic and survives a destroy/recreate of the environment.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "unseal" {
  description             = "Vault auto-unseal key for ${var.name_prefix}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "unseal" {
  name          = "alias/${var.name_prefix}-vault-unseal"
  target_key_id = aws_kms_key.unseal.key_id
}

data "aws_iam_policy_document" "unseal" {
  statement {
    sid       = "VaultAutoUnseal"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.unseal.arn]
  }
}

resource "aws_iam_policy" "unseal" {
  name        = "${var.name_prefix}-vault-unseal"
  description = "Lets the Vault server pods use the auto-unseal key."
  policy      = data.aws_iam_policy_document.unseal.json

  tags = var.tags
}

module "unseal_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "${var.name_prefix}-vault-unseal"
  provider_url                  = var.oidc_provider
  role_policy_arns              = [aws_iam_policy.unseal.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.namespace}:${var.service_account}"]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Destination for the output of `vault operator init` (recovery keys, root
# token, CA certificate). Only the init job's service account may write it.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "init" {
  name                    = local.init_secret_name
  description             = "Vault init output for ${var.name_prefix}: recovery keys, root token and CA. Written once by the init job."
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = var.tags
}

data "aws_iam_policy_document" "init" {
  statement {
    sid = "WriteVaultInitOutput"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = [aws_secretsmanager_secret.init.arn]
  }
}

resource "aws_iam_policy" "init" {
  name        = "${var.name_prefix}-vault-init"
  description = "Lets the Vault init job store the init output in Secrets Manager."
  policy      = data.aws_iam_policy_document.init.json

  tags = var.tags
}

module "init_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "${var.name_prefix}-vault-init"
  provider_url                  = var.oidc_provider
  role_policy_arns              = [aws_iam_policy.init.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.namespace}:${var.init_service_account}"]

  tags = var.tags
}
