variable "cluster_name" {
  description = "Name of the EKS cluster. Also used as the prefix for the IAM roles this module creates."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,39}$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, start with a letter or digit, and contain only letters, digits, hyphens and underscores. The length limit keeps derived IAM role names under 64 characters."
  }
}

variable "cluster_version" {
  description = "Kubernetes minor version for the control plane, for example \"1.33\"."
  type        = string
  default     = "1.33"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.cluster_version))
    error_message = "cluster_version must be a Kubernetes minor version such as \"1.33\"."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the cluster is created in."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "subnet_ids" {
  description = "Subnets for the control plane network interfaces and the managed node groups. Use private subnets in at least two availability zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets in different availability zones."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint on the internet. Set to false for a private cluster, in which case Terraform must run from inside the VPC."
  type        = bool
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant the IAM identity that runs Terraform cluster-admin access through an EKS access entry."
  type        = bool
  default     = true
}

variable "ami_type" {
  description = "AMI family for all managed node groups. Amazon Linux 2 images are not published for Kubernetes 1.33 and later, so AL2023 is the default."
  type        = string
  default     = "AL2023_x86_64_STANDARD"

  validation {
    condition = contains([
      "AL2023_x86_64_STANDARD",
      "AL2023_ARM_64_STANDARD",
      "AL2023_x86_64_NVIDIA",
      "AL2_x86_64",
      "AL2_x86_64_GPU",
      "AL2_ARM_64",
      "BOTTLEROCKET_x86_64",
      "BOTTLEROCKET_ARM_64",
    ], var.ami_type)
    error_message = "ami_type must be one of the EKS managed node group AMI types (AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD, AL2023_x86_64_NVIDIA, AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, BOTTLEROCKET_x86_64, BOTTLEROCKET_ARM_64)."
  }
}

variable "node_groups" {
  description = "Managed node groups keyed by a short name. The key becomes the node group name prefix and part of its IAM role name."
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
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }

  validation {
    condition     = length(var.node_groups) > 0
    error_message = "At least one node group is required."
  }

  validation {
    condition     = alltrue([for key in keys(var.node_groups) : can(regex("^[a-z0-9][a-z0-9-]{0,17}$", key))])
    error_message = "Node group keys must be 1-18 lowercase alphanumeric characters or hyphens, starting with a letter or digit."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : length(ng.instance_types) > 0])
    error_message = "Every node group needs at least one instance type."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : ng.min_size >= 0 && ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size])
    error_message = "Every node group must satisfy 0 <= min_size <= desired_size <= max_size."
  }

  validation {
    condition     = alltrue([for ng in var.node_groups : contains(["ON_DEMAND", "SPOT"], ng.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue(flatten([for ng in var.node_groups : [for t in ng.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)]]))
    error_message = "Taint effects must be NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  }
}

variable "cluster_addons" {
  description = "Additional EKS add-ons keyed by add-on name, for example coredns or vpc-cni. The EBS CSI driver is always installed with its own IAM role and does not need to be listed."
  type = map(object({
    addon_version        = optional(string)
    most_recent          = optional(bool, true)
    configuration_values = optional(string)
  }))
  default = {}

  validation {
    condition     = !contains(keys(var.cluster_addons), "aws-ebs-csi-driver")
    error_message = "aws-ebs-csi-driver is managed by this module and cannot be overridden through cluster_addons."
  }
}

variable "kms_key_deletion_window_in_days" {
  description = "Days AWS KMS waits before deleting the cluster's secrets-encryption key once the cluster is destroyed. Use the minimum (7) for short-lived environments so recreated clusters do not pile up keys pending deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30 && floor(var.kms_key_deletion_window_in_days) == var.kms_key_deletion_window_in_days
    error_message = "kms_key_deletion_window_in_days must be a whole number between 7 and 30, the range AWS KMS accepts."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
