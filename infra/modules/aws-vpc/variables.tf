variable "name" {
  description = "Name of the VPC. Used as the Name tag and as the prefix for subnet, route table and NAT gateway names."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 64
    error_message = "name must be between 1 and 64 characters."
  }
}

variable "cidr_block" {
  description = "IPv4 CIDR block for the VPC. Subnets are carved out of this block, so pick a range that does not overlap with networks you plan to peer with."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR block, for example 10.0.0.0/16."
  }

  validation {
    condition     = try(tonumber(split("/", var.cidr_block)[1]), 0) >= 16 && try(tonumber(split("/", var.cidr_block)[1]), 99) <= 28
    error_message = "AWS only allows VPC prefix lengths between /16 and /28."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across. One private and one public subnet are created in each zone."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6 && floor(var.az_count) == var.az_count
    error_message = "az_count must be a whole number between 2 and 6. EKS requires subnets in at least two availability zones."
  }
}

variable "subnet_prefix_length" {
  description = "Prefix length of every subnet. With the default /16 VPC and /24 subnets each subnet has 251 usable addresses, which is enough for the pods of a small cluster."
  type        = number
  default     = 24

  validation {
    condition     = var.subnet_prefix_length <= 28 && var.subnet_prefix_length > try(tonumber(split("/", var.cidr_block)[1]), 0)
    error_message = "subnet_prefix_length must be larger than the VPC prefix length and at most 28 (the smallest subnet AWS allows)."
  }

  validation {
    condition     = pow(2, var.subnet_prefix_length - try(tonumber(split("/", var.cidr_block)[1]), var.subnet_prefix_length)) >= 2 * var.az_count
    error_message = "The VPC is too small to hold two subnets per availability zone at this subnet_prefix_length. Use a larger VPC, a larger subnet_prefix_length, or fewer zones."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so that workloads in the private subnets (including EKS nodes) can reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway between all private subnets instead of creating one per availability zone. Cheaper, but a single point of failure; set to false for production."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
