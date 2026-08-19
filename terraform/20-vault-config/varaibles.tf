#------------------------------------------------------------------------
# Hashi Platform: HCP Vault - Variables
#------------------------------------------------------------------------


variable "vault_address" {
  description = "The address of the Vault server"
  type        = string
}

variable "vault_token" {
  description = "The token for authenticating with the Vault server"
  type        = string
}