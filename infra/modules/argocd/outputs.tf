output "namespace" {
  description = "Namespace Argo CD runs in."
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

output "cluster_secret_name" {
  description = "Name of the in-cluster registration secret that carries the labels and annotations."
  value       = kubernetes_secret_v1.in_cluster.metadata[0].name
}

output "port_forward_command" {
  description = "Command that exposes the Argo CD UI on http://localhost:8080."
  value       = "kubectl -n ${kubernetes_namespace_v1.this.metadata[0].name} port-forward svc/argocd-server 8080:80"
}

output "initial_admin_password_command" {
  description = "Command that prints the initial admin password."
  value       = "kubectl -n ${kubernetes_namespace_v1.this.metadata[0].name} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
