variable "enabled" {
  description = "Create the HCP Boundary cluster. Off by default: the module is a placeholder until the access layer is built out."
  type        = bool
  default     = false
}

variable "cluster_id" {
  description = "ID (and DNS label) of the HCP Boundary cluster, for example hashi-platform-production."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,35}$", var.cluster_id))
    error_message = "cluster_id must be 3-36 lowercase alphanumeric characters or hyphens."
  }
}

variable "tier" {
  description = "HCP Boundary tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Plus"], var.tier)
    error_message = "tier must be Standard or Plus."
  }
}

variable "admin_username" {
  description = "Initial administrator login name for the Boundary cluster."
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Initial administrator password. Provide it through an HCP Terraform sensitive variable, never in tfvars."
  type        = string
  sensitive   = true
  default     = null
}
