variable "chart_version" {
  description = "Version of the jetstack/cert-manager Helm chart."
  type        = string
  default     = "1.21.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be an exact semantic version such as 1.21.1."
  }
}

variable "namespace" {
  description = "Namespace created for cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "keep_crds_on_uninstall" {
  description = "Keep the cert-manager CRDs (and therefore every Certificate and Issuer) when the release is removed. Leave false for ephemeral environments."
  type        = bool
  default     = false
}
