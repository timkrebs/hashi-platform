# ------------------------------------------------------------------------
# Hashi Platform: Sentinel policy set
#
# Each policy runs against the Terraform plan (tfplan/v2) after `terraform
# plan` and before `terraform apply`. The enforcement_level decides what
# happens when a policy fails:
#
#   advisory       - warning only, the run continues to apply
#   soft-mandatory - run is blocked, but an authorized user can override
#   hard-mandatory - run is blocked, no override possible
# ------------------------------------------------------------------------

policy "restrict-eks-public-endpoint" {
  source            = "./restrict-eks-public-endpoint.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "vault-pki-secure-role" {
  source            = "./vault-pki-secure-role.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "restrict-instance-types" {
  source            = "./restrict-instance-types.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "require-mandatory-tags" {
  source            = "./require-mandatory-tags.sentinel"
  enforcement_level = "advisory"
}
