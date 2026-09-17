variable "name" {
  description = "Name of the monitoring server. Used as the Name tag and as the prefix for the security group, IAM role, instance profile and SSM parameter."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,31}$", var.name))
    error_message = "name must be 3 to 32 lowercase alphanumeric characters or hyphens, starting with a letter or digit."
  }
}

variable "region" {
  description = "AWS region the server runs in. The instance uses it to read its admin password from SSM at boot, and it scopes the kms:Decrypt grant to the SSM service."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security group is created in."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,}$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "subnet_id" {
  description = "Public subnet the instance is launched into. It must route to an internet gateway: the bootstrap downloads the Checkmk package and the interface is served over the elastic IP."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,}$", var.subnet_id))
    error_message = "subnet_id must be a subnet ID such as subnet-0123456789abcdef0."
  }
}

variable "instance_type" {
  description = "EC2 instance type. Checkmk Raw needs about 2 GB of RAM for a small site; t3.medium gives 4 GB, which suits a handful of monitored hosts."
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like t3.medium."
  }

  validation {
    condition     = contains(["nano", "micro", "small", "medium"], try(split(".", var.instance_type)[1], ""))
    error_message = "instance_type must be nano, micro, small or medium. The restrict-compute-size policy rejects anything larger."
  }
}

variable "root_volume_size" {
  description = "Size of the encrypted gp3 root volume in GiB. The package alone needs roughly 2 GiB; the rest holds monitoring history."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000 && floor(var.root_volume_size) == var.root_volume_size
    error_message = "root_volume_size must be a whole number between 20 and 1000 GiB."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the web interface. Port 80 only redirects to 443. Defaults to the whole internet; narrow it to an office or VPN range where you can, because the certificate is self-signed."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "allowed_cidr_blocks must contain at least one CIDR block, otherwise the interface is unreachable."
  }

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrnetmask(cidr))])
    error_message = "allowed_cidr_blocks must contain valid IPv4 CIDR blocks, for example 203.0.113.0/24."
  }
}

variable "site_name" {
  description = "Name of the OMD site. The interface is served under https://<address>/<site_name>/."
  type        = string
  default     = "cmk"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,15}$", var.site_name))
    error_message = "site_name must start with a lowercase letter and be at most 16 lowercase letters, digits or underscores."
  }
}

variable "package_url" {
  description = "Download URL of the Checkmk Raw Edition package. It must be the Ubuntu 24.04 (noble) amd64 build, because the instance runs Ubuntu 24.04."
  type        = string
  default     = "https://download.checkmk.com/checkmk/2.4.0p36/check-mk-raw-2.4.0p36_0.noble_amd64.deb"

  validation {
    condition     = can(regex("^https://", var.package_url))
    error_message = "package_url must be an https URL. The package is verified by checksum but must not travel in clear text."
  }

  validation {
    condition     = can(regex("noble_amd64\\.deb$", var.package_url))
    error_message = "package_url must point at a _0.noble_amd64.deb build to match the Ubuntu 24.04 AMI."
  }
}

variable "package_sha256" {
  description = "SHA256 of the Checkmk package, pinned on purpose. Refresh it from <package_url>.hash when bumping the version. The instance never fetches that sidecar, because whoever can serve a bad package can serve a matching hash."
  type        = string
  default     = "8208d6a1725bbba9e44867d2759b0a3638c019d71e4e426cf5d2aa6bdb92416a"

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.package_sha256))
    error_message = "package_sha256 must be 64 lowercase hexadecimal characters."
  }
}

variable "ami_owner" {
  description = "Account that publishes the hardened base image. Defaults to the company ami-prod account."
  type        = string
  default     = "888995627335"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.ami_owner))
    error_message = "ami_owner must be a 12-digit AWS account ID."
  }
}

variable "ami_name_prefix" {
  description = "Name prefix of the hardened image, without the build timestamp. It must be an Ubuntu 24.04 (noble) family, because the pinned Checkmk package is a noble build."
  type        = string
  default     = "hc-base-ubuntu-2404-amd64"

  validation {
    condition     = can(regex("ubuntu-2404", var.ami_name_prefix))
    error_message = "ami_name_prefix must be an ubuntu-2404 image family to match the noble Checkmk package."
  }

  validation {
    condition     = !can(regex("-eks-", var.ami_name_prefix))
    error_message = "ami_name_prefix must not be an -eks- variant; those carry kubelet and belong on EKS node groups, not on a standalone server."
  }
}

variable "ami_id" {
  description = "Pin a specific AMI instead of looking up the newest hardened image. Leave null unless you need a reproducible rebuild."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,}$", var.ami_id))
    error_message = "ami_id must be null or an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "admin_password_length" {
  description = "Length of the generated cmkadmin password stored in SSM Parameter Store."
  type        = number
  default     = 24

  validation {
    condition     = var.admin_password_length >= 16 && var.admin_password_length <= 64 && floor(var.admin_password_length) == var.admin_password_length
    error_message = "admin_password_length must be a whole number between 16 and 64."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this module. Environment, Project and ManagedBy are mandatory for the Sentinel policy set."
  type        = map(string)
  default     = {}
}
