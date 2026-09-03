variable "name" {
  description = "Name of the root Application."
  type        = string
  default     = "root"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.name))
    error_message = "name must be a lowercase DNS label."
  }
}

variable "namespace" {
  description = "Namespace Argo CD runs in; the Application is created there."
  type        = string
  default     = "argocd"
}

variable "repo_url" {
  description = "Git repository Argo CD syncs from."
  type        = string

  validation {
    condition     = can(regex("^(https://|git@|ssh://)", var.repo_url))
    error_message = "repo_url must be an https://, ssh:// or git@ URL."
  }
}

variable "target_revision" {
  description = "Branch, tag or commit to track."
  type        = string
}

variable "path" {
  description = "Directory in the repository that holds the Applications and ApplicationSets to sync."
  type        = string
}

variable "project" {
  description = "Argo CD project the root Application belongs to."
  type        = string
  default     = "default"
}

variable "destination_server" {
  description = "Cluster the child manifests are applied to."
  type        = string
  default     = "https://kubernetes.default.svc"
}

variable "automated_sync" {
  description = "Sync automatically with prune and self-heal. Disable to review syncs by hand in the UI."
  type        = bool
  default     = true
}

variable "apps_chart_version" {
  description = "Version of the argo/argocd-apps Helm chart used to render the Application."
  type        = string
  default     = "2.0.5"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.apps_chart_version))
    error_message = "apps_chart_version must be an exact semantic version such as 2.0.5."
  }
}

variable "uninstall_timeout" {
  description = "Seconds Helm waits for the Application and everything it manages to be deleted when the release is removed."
  type        = number
  default     = 600

  validation {
    condition     = var.uninstall_timeout >= 60 && var.uninstall_timeout <= 3600
    error_message = "uninstall_timeout must be between 60 and 3600 seconds."
  }
}
