output "cluster_url" {
  description = "Boundary control-plane URL — consumed by 7-boundary's boundary provider and `boundary authenticate password -addr <url>`"
  value       = hcp_boundary_cluster.main.cluster_url
}

output "cluster_uuid" {
  description = "Boundary cluster UUID (host prefix of cluster_url), needed by the egress worker config"
  value       = regex("^https://([0-9a-f-]+)\\.", hcp_boundary_cluster.main.cluster_url)[0]
}
