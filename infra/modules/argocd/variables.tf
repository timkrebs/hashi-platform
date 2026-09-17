variable "chart_version" {
  description = "Version of the argo/argo-cd Helm chart."
  type        = string
  default     = "10.7.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be an exact semantic version such as 10.7.1."
  }
}

variable "namespace" {
  description = "Namespace created for Argo CD."
  type        = string
  default     = "argocd"
}

variable "server_insecure" {
  description = "Serve the Argo CD API and UI over plain HTTP inside the cluster. Fine while the UI is reached through kubectl port-forward; set to false once an ingress terminates TLS."
  type        = bool
  default     = true
}

variable "cluster_secret_labels" {
  description = "Extra labels on the in-cluster registration secret. ApplicationSets select the cluster by these labels."
  type        = map(string)
  default     = {}
}

variable "cluster_secret_annotations" {
  description = "Annotations on the in-cluster registration secret. This is how Terraform hands values (account id, IAM role ARNs, KMS alias, allow-lists) to ApplicationSet templates."
  type        = map(string)
  default     = {}
}

variable "additional_values" {
  description = "Extra Helm values documents (YAML strings) merged after the module's defaults."
  type        = list(string)
  default     = []
}
