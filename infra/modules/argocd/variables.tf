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
  description = "Serve the Argo CD API and UI over plain HTTP inside the cluster. Fine while the UI is only reached through kubectl port-forward. Ignored when service_type is LoadBalancer, because the NLB passes TCP through and argocd-server has to terminate TLS itself."
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

variable "service_type" {
  description = "Service type for the Argo CD server. LoadBalancer puts an internet-facing network load balancer in front of the UI; ClusterIP keeps it reachable only through port-forward."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be ClusterIP, NodePort or LoadBalancer."
  }
}

variable "load_balancer_source_ranges" {
  description = "CIDR blocks allowed to reach the Argo CD UI when service_type is LoadBalancer. Defaults to the whole internet; narrow it wherever you can, because this is the control plane for everything the cluster runs."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.load_balancer_source_ranges : can(cidrnetmask(cidr))])
    error_message = "load_balancer_source_ranges must contain valid IPv4 CIDR blocks, for example 203.0.113.0/24."
  }
}
