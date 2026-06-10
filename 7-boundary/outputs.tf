output "boundary_cluster_url" {
  description = "Boundary control-plane URL — use with `boundary authenticate password -addr <url>`"
  value       = data.tfe_outputs.boundary_cluster.nonsensitive_values.cluster_url
}

output "demo_target_private_ip" {
  description = "Private IP of the throwaway demo target (null when disabled)"
  value       = var.enable_demo_target ? aws_instance.demo_target[0].private_ip : null
}

output "egress_worker_instance_id" {
  description = "EC2 instance ID of the self-managed egress worker"
  value       = aws_instance.egress_worker.id
}

output "scope_ids" {
  description = "Boundary scope IDs (org and platform project)"
  value = {
    org      = boundary_scope.org.id
    platform = boundary_scope.platform.id
  }
}

output "ssh_target_id" {
  description = "Target ID for `boundary connect ssh -target-id <id>`"
  value       = boundary_target.private_ssh.id
}
