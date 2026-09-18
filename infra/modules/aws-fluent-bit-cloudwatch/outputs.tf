output "iam_role_arn" {
  description = "IAM role Fluent Bit assumes through IRSA. Annotate its service account with this."
  value       = module.irsa.iam_role_arn
}

output "log_group_name" {
  description = "CloudWatch log group the container logs are written to."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the log group."
  value       = aws_cloudwatch_log_group.this.arn
}
