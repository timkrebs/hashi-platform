variable "aws_region" {
  description = "AWS region (must match the network layer)"
  type        = string
  default     = "eu-central-1"
}

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

variable "demo_target_instance_type" {
  description = "Instance type of the throwaway demo SSH target"
  type        = string
  default     = "t3.micro"
}

variable "enable_demo_target" {
  description = "Create a throwaway private-subnet SSH target to prove the end-to-end session flow before Layers 4-6 provide real targets. Set false to destroy it"
  type        = bool
  default     = true
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
  default     = "tim"
}

variable "tfc_organization" {
  description = "HCP Terraform organization that owns the layer workspaces (used to read earlier layers' outputs)"
  type        = string
  default     = "tim-krebs-org"
}

variable "worker_instance_type" {
  description = "Instance type of the self-managed egress worker"
  type        = string
  default     = "t3.micro"
}
