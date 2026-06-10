variable "boundary_admin_password" {
  description = "Password of the initial Boundary admin user (set once as a sensitive workspace variable; minimum 8 characters)"
  type        = string
  sensitive   = true
}

variable "boundary_admin_username" {
  description = "Login name of the initial Boundary admin user"
  type        = string
  default     = "admin"
}

variable "boundary_tier" {
  description = "HCP Boundary tier. Plus is required for SSH credential injection (the Vault-signed cert never reaches the client)"
  type        = string
  default     = "Plus"

  validation {
    condition     = contains(["Standard", "Plus"], var.boundary_tier)
    error_message = "boundary_tier must be \"Standard\" or \"Plus\"."
  }
}
