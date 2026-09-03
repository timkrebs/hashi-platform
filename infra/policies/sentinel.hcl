# Sentinel policy set for the hashi-platform project in HCP Terraform.
#
# Attached as a VCS-backed policy set with policies path "infra/policies".
# Every run in the project is evaluated against these policies after the plan.
#
# Enforcement levels:
#   advisory        log only
#   soft-mandatory  block, but users with the right permission can override
#   hard-mandatory  block, no override

policy "require-mandatory-tags" {
  source            = "./require-mandatory-tags.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "restrict-compute-size" {
  source            = "./restrict-compute-size.sentinel"
  enforcement_level = "hard-mandatory"
}
