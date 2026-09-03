# Unit tests: plan mode with a mocked helm provider. No cluster access needed.
#
#   cd infra/modules/argocd-root-app && terraform init -backend=false && terraform test

mock_provider "helm" {}

variables {
  repo_url        = "https://github.com/timkrebs/hashi-platform.git"
  target_revision = "dev"
  path            = "gitops/clusters/dev"
}

run "renders_root_application_with_finalizer_and_automation" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.this.values[0]).applications.root.source.path == "gitops/clusters/dev" && yamldecode(helm_release.this.values[0]).applications.root.source.targetRevision == "dev"
    error_message = "The root Application should track the requested path and revision."
  }

  assert {
    condition     = contains(yamldecode(helm_release.this.values[0]).applications.root.finalizers, "resources-finalizer.argocd.argoproj.io")
    error_message = "The resources finalizer is what makes destroys cascade; it must be present."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).applications.root.syncPolicy.automated.prune == true && yamldecode(helm_release.this.values[0]).applications.root.syncPolicy.automated.selfHeal == true
    error_message = "Automated sync with prune and self-heal should be on by default."
  }

  assert {
    condition     = helm_release.this.wait == true && helm_release.this.timeout == 600 && helm_release.this.version == "2.0.5"
    error_message = "Helm should wait (also on uninstall) with the configured timeout."
  }
}

run "manual_sync_drops_automation_only" {
  command = plan

  variables {
    automated_sync = false
  }

  assert {
    condition     = !contains(keys(yamldecode(helm_release.this.values[0]).applications.root.syncPolicy), "automated")
    error_message = "automated should be absent when automated_sync is false."
  }

  assert {
    condition     = contains(yamldecode(helm_release.this.values[0]).applications.root.syncPolicy.syncOptions, "CreateNamespace=true")
    error_message = "syncOptions should stay in place."
  }
}

run "rejects_plain_http_repo_url" {
  command = plan

  variables {
    repo_url = "http://github.com/timkrebs/hashi-platform.git"
  }

  expect_failures = [var.repo_url]
}

run "rejects_unreasonable_uninstall_timeout" {
  command = plan

  variables {
    uninstall_timeout = 10
  }

  expect_failures = [var.uninstall_timeout]
}
