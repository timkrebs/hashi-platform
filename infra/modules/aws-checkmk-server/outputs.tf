output "instance_id" {
  description = "ID of the Checkmk instance."
  value       = aws_instance.this.id
}

output "ami_id" {
  description = "AMI the instance was launched from. Pin it through ami_id to rebuild the same image later."
  value       = local.ami_id
}

output "private_ip" {
  description = "Private address of the instance inside the VPC."
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Elastic IP of the instance. Stable across a stop and start."
  value       = aws_eip.this.public_ip
}

output "url" {
  description = "URL of the Checkmk web interface. The certificate is self-signed, so browsers warn on the first visit."
  value       = "https://${aws_eip.this.public_ip}/${var.site_name}/"
}

output "site_name" {
  description = "Name of the OMD site."
  value       = var.site_name
}

output "security_group_id" {
  description = "Security group attached to the instance."
  value       = aws_security_group.this.id
}

output "iam_role_arn" {
  description = "ARN of the instance role, for attaching further policies from the root."
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the instance role."
  value       = aws_iam_role.this.name
}

output "admin_password_parameter_name" {
  description = "SSM parameter holding the initial cmkadmin password."
  value       = aws_ssm_parameter.admin_password.name
}

output "admin_password_parameter_arn" {
  description = "ARN of the SSM parameter holding the initial cmkadmin password."
  value       = aws_ssm_parameter.admin_password.arn
}

# The password itself is deliberately not an output: it would appear in
# `terraform output` and in the HCP Terraform run UI. Reading it through the
# command below leaves an audit trail instead.
output "admin_password_command" {
  description = "Command that prints the initial cmkadmin password."
  value       = "aws ssm get-parameter --region ${var.region} --name ${aws_ssm_parameter.admin_password.name} --with-decryption --query Parameter.Value --output text"
}

output "session_manager_command" {
  description = "Command that opens a shell on the instance through SSM Session Manager."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.this.id}"
}
