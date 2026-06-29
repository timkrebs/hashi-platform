# Sentinel policy set for hashi-platform.
#
# Attach this policy set to the hashi-platform-dev, -staging, and -prod
# workspaces in HCP Terraform. Each policy derives the target environment from
# the workspace name (hashi-platform-<env>) and applies environment-specific
# guardrails, so the same set serves all three workspaces.

policy "restrict-node-instance-types" {
  source            = "./restrict-node-instance-types.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "limit-node-group-size" {
  source            = "./limit-node-group-size.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "require-environment-tags" {
  source            = "./require-environment-tags.sentinel"
  enforcement_level = "advisory"
}

policy "enforce-cost-by-environment" {
  source            = "./enforce-cost-by-environment.sentinel"
  enforcement_level = "advisory"
}
