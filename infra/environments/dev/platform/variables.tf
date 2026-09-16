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
