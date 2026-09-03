# Unit tests: plan mode with mocked providers. No cluster access needed.
#
#   cd infra/modules/cert-manager && terraform init -backend=false && terraform test

mock_provider "helm" {}
mock_provider "kubernetes" {}

run "installs_pinned_chart_with_crds" {
  command = plan

  assert {
    condition     = output.namespace == "cert-manager" && helm_release.this.namespace == "cert-manager"
    error_message = "cert-manager should be installed into its own namespace."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).crds.enabled == true && yamldecode(helm_release.this.values[0]).crds.keep == false
    error_message = "CRDs should be installed with the chart and removed on uninstall by default."
  }

  assert {
    condition     = helm_release.this.version == "1.21.1" && helm_release.this.wait == true
    error_message = "Release should install the pinned chart and wait for readiness."
  }
}

run "keeps_crds_when_asked" {
  command = plan

  variables {
    keep_crds_on_uninstall = true
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).crds.keep == true
    error_message = "keep_crds_on_uninstall should be passed to the chart."
  }
}

run "rejects_unpinned_chart_version" {
  command = plan

  variables {
    chart_version = "v1"
  }

  expect_failures = [var.chart_version]
}
