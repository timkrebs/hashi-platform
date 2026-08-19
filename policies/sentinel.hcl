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
#
# The current hashi-platform code is compliant with every policy in this
# set, so a run passes the policy check and proceeds to apply.
# ------------------------------------------------------------------------

policy "restrict-aws-regions" {
  source            = "./restrict-aws-regions.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "eks-approved-cluster-version" {
  source            = "./eks-approved-cluster-version.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "vault-approved-secret-engines" {
  source            = "./vault-approved-secret-engines.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "restrict-instance-types" {
  source            = "./restrict-instance-types.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "enforce-tagging-standard" {
  source            = "./enforce-tagging-standard.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "eks-node-group-size-limits" {
  source            = "./eks-node-group-size-limits.sentinel"
  enforcement_level = "advisory"
}
