output "kms_key_arn" {
  description = "ARN of the auto-unseal KMS key."
  value       = aws_kms_key.unseal.arn
}

output "kms_key_id" {
  description = "ID of the auto-unseal KMS key."
  value       = aws_kms_key.unseal.key_id
}

output "kms_key_alias" {
  description = "Alias of the auto-unseal key (alias/...); pass it to Vault's awskms seal as kms_key_id."
  value       = aws_kms_alias.unseal.name
}

output "vault_irsa_role_arn" {
  description = "ARN of the IAM role the Vault server service account assumes to use the unseal key."
  value       = module.unseal_irsa.iam_role_arn
}

output "vault_init_irsa_role_arn" {
  description = "ARN of the IAM role the init job's service account assumes to write the init secret."
  value       = module.init_irsa.iam_role_arn
}

output "init_secret_arn" {
  description = "ARN of the Secrets Manager secret that receives the init output."
  value       = aws_secretsmanager_secret.init.arn
}

output "init_secret_name" {
  description = "Name of the Secrets Manager secret that receives the init output."
  value       = aws_secretsmanager_secret.init.name
}
