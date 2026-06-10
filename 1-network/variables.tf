variable "aws_region" {
  description = "AWS region; subnets spread over its a/b/c availability zones"
  type        = string
  default     = "eu-central-1"
}

variable "hvn_cidr" {
  description = "HCP HVN CIDR. PERMANENT — never change after creation; a change forces destroying every HCP cluster inside the HVN"
  type        = string
  default     = "172.25.16.0/20"
}

variable "nat_gateway_strategy" {
  description = "NAT topology: 'single' (one NAT, ~1/3 the cost, cross-AZ traffic and an availability single point of failure) or 'per_az' (production posture: one NAT per AZ)"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "per_az"], var.nat_gateway_strategy)
    error_message = "nat_gateway_strategy must be \"single\" or \"per_az\"."
  }
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
  default     = "tim"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR per AZ suffix — Consul/Nomad servers, Nomad clients, Boundary egress worker"
  type        = map(string)
  default = {
    a = "10.0.10.0/24"
    b = "10.0.11.0/24"
    c = "10.0.12.0/24"
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR per AZ suffix — NAT gateways only, nothing else launches here"
  type        = map(string)
  default = {
    a = "10.0.0.0/24"
    b = "10.0.1.0/24"
    c = "10.0.2.0/24"
  }
}

variable "vpc_cidr" {
  description = "Primary workload VPC CIDR; must never overlap the HVN CIDR"
  type        = string
  default     = "10.0.0.0/16"
}
