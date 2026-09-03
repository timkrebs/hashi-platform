# Unit tests: plan mode with a mocked hcp provider. No HCP access needed.
#
#   cd infra/modules/boundary && terraform init -backend=false && terraform test

mock_provider "hcp" {}

variables {
  cluster_id = "hashi-platform-dev"
}

run "disabled_by_default_creates_nothing" {
  command = plan

  assert {
    condition     = length(hcp_boundary_cluster.this) == 0 && output.cluster_url == null
    error_message = "The placeholder must not create a Boundary cluster unless enabled."
  }
}

run "enabled_creates_the_control_plane" {
  command = plan

  variables {
    enabled        = true
    admin_password = "unit-test-only"
  }

  assert {
    condition     = length(hcp_boundary_cluster.this) == 1 && hcp_boundary_cluster.this[0].cluster_id == "hashi-platform-dev" && hcp_boundary_cluster.this[0].tier == "Standard"
    error_message = "Enabling the module should create exactly one Standard-tier cluster with the given id."
  }
}

run "rejects_invalid_cluster_id" {
  command = plan

  variables {
    cluster_id = "Hashi_Platform"
  }

  expect_failures = [var.cluster_id]
}

run "rejects_unknown_tier" {
  command = plan

  variables {
    tier = "Enterprise"
  }

  expect_failures = [var.tier]
}
