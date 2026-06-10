variable "agent_token_ssm_parameter" {
  description = "SSM parameter holding the agent token (written by 0-bootstrap — keep in sync with its locals)"
  type        = string
  default     = "/hashi-platform/tfc-agent-token"
}

variable "aws_region" {
  description = "AWS region (must match the network layer)"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "Agent instance type; 2 GiB memory minimum for terraform runs"
  type        = string
  default     = "t3.small"
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
  default     = "tim"
}

variable "tfc_agent_version" {
  description = "tfc-agent version installed at boot; TFC_AGENT_AUTO_UPDATE=minor keeps it current afterwards"
  type        = string
  default     = "1.15.4"
}

variable "tfc_organization" {
  description = "HCP Terraform organization that owns the layer workspaces (used to read 1-network outputs)"
  type        = string
  default     = "tim-krebs-org"
}
