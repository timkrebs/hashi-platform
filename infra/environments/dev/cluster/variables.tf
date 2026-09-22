variable "region" {
  description = "AWS region the environment is deployed to."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "IPv4 CIDR block for the environment VPC. Keep it unique per environment so the VPCs can be peered later."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use for subnets and nodes."
  type        = number
  default     = 3
}

variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane."
  type        = string
  default     = "1.36"
}

variable "use_hardened_node_ami" {
  description = "Run the managed node groups on the company's hardened EKS image. Only turn this on once cluster_version matches a published hc-base-ubuntu-2404-eks-<version> image, otherwise the plan fails on the AMI lookup."
  type        = bool
  default     = false
}

variable "node_groups" {
  description = "Managed node groups for the cluster, keyed by a short name. See modules/aws-eks-cluster for the full schema."
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    capacity_type  = optional(string, "ON_DEMAND")
    labels         = optional(map(string), {})
    taints = optional(map(object({
      key    = string
      value  = optional(string)
      effect = string
    })), {})
  }))
  default = {
    default = {
      instance_types = ["t3.large"]
      min_size       = 3
      max_size       = 6
      desired_size   = 3
    }
  }
}
