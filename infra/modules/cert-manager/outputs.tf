output "namespace" {
  description = "Namespace cert-manager runs in."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "release_name" {
  description = "Name of the Helm release."
  value       = helm_release.this.name
}

output "chart_version" {
  description = "Installed chart version."
  value       = helm_release.this.version
}
