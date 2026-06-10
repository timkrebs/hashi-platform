variable "ssh_mount_path" {
  description = "Mount path of the SSH certificate signing engine (client signer for Boundary sessions)"
  type        = string
  default     = "ssh-client-signer"
}

variable "tfc_organization" {
  description = "HCP Terraform organization that owns the layer workspaces (used to read 2-vault-cluster outputs)"
  type        = string
  default     = "tim-krebs-org"
}
