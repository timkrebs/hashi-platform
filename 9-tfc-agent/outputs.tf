output "agent_asg_name" {
  description = "Auto Scaling group running the agent (size 1, self-healing)"
  value       = aws_autoscaling_group.agent.name
}

output "agent_security_group_id" {
  description = "Outbound-only security group of the agent instance"
  value       = aws_security_group.agent.id
}
