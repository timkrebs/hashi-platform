variable "region" {
  description = "AWS region the environment is deployed to."
  type        = string
  default     = "us-east-1"
}

variable "enable_cert_manager" {
  description = "Install cert-manager, the issuer for in-cluster TLS certificates."
  type        = bool
  default     = true
}

variable "enable_checkmk" {
  description = "Create the Checkmk monitoring server on EC2."
  type        = bool
  default     = true
}

variable "checkmk_instance_type" {
  description = "EC2 instance type for the Checkmk server. The restrict-compute-size policy caps this at medium."
  type        = string
  default     = "t3.medium"
}

variable "checkmk_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Checkmk web interface. Defaults to the whole internet, and the certificate is self-signed, so narrow this where you can."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
