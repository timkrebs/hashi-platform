output "enabled" {
  description = "Whether the HCP Boundary cluster is managed by this module."
  value       = var.enabled
}

output "cluster_id" {
  description = "ID of the HCP Boundary cluster."
  value       = var.cluster_id
}

output "cluster_url" {
  description = "URL of the HCP Boundary cluster, or null while the module is disabled."
  value       = try(hcp_boundary_cluster.this[0].cluster_url, null)
}
