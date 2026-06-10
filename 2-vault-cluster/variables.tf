variable "tfc_organization" {
  description = "HCP Terraform organization that owns the layer workspaces (used to read 1-network outputs)"
  type        = string
  default     = "tim-krebs-org"
}

variable "tier" {
  description = "HCP Vault Dedicated tier. dev = single node, no HA, lowest cost — right-sized for this build-out; switch to standard_small for the 3-node HA production posture"
  type        = string
  default     = "dev"

  validation {
    condition = contains([
      "dev",
      "starter_small",
      "standard_small", "standard_medium", "standard_large",
      "plus_small", "plus_medium", "plus_large",
    ], var.tier)
    error_message = "tier must be a valid HCP Vault Dedicated tier (dev, starter_small, standard_small/medium/large, plus_small/medium/large)."
  }
}

variable "vault_cluster_id" {
  description = "ID (and display name) of the HCP Vault Dedicated cluster"
  type        = string
  default     = "hashi-platform-vault"
}
