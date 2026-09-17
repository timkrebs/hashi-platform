# Unit tests: plan mode with mocked providers. No cluster access needed.
#
#   cd infra/modules/argocd && terraform init -backend=false && terraform test

mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_secret_labels = {
    "hashi-platform.io/environment" = "dev"
  }
  cluster_secret_annotations = {
    "hashi-platform.io/environment"         = "dev"
    "hashi-platform.io/vault-kms-key-alias" = "alias/hashi-platform-dev-vault-unseal"
  }
}

run "installs_a_minimal_argocd" {
  command = plan

  assert {
    condition     = output.namespace == "argocd" && helm_release.this.version == "10.7.1" && helm_release.this.wait == true
    error_message = "Argo CD should be installed into its namespace from the pinned chart."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).dex.enabled == false && yamldecode(helm_release.this.values[0]).notifications.enabled == false
    error_message = "Dex and notifications should be disabled."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).configs.params["server.insecure"] == true
    error_message = "The API server should run insecure by default (UI via port-forward)."
  }
}

run "registers_the_local_cluster_with_labels_and_annotations" {
  command = plan

  assert {
    condition     = nonsensitive(kubernetes_secret_v1.in_cluster.data["server"]) == "https://kubernetes.default.svc" && nonsensitive(kubernetes_secret_v1.in_cluster.data["name"]) == "in-cluster"
    error_message = "The cluster secret must point at the local API server under the name in-cluster."
  }

  assert {
    condition     = kubernetes_secret_v1.in_cluster.metadata[0].labels["argocd.argoproj.io/secret-type"] == "cluster" && kubernetes_secret_v1.in_cluster.metadata[0].labels["hashi-platform.io/environment"] == "dev"
    error_message = "The cluster secret needs the Argo CD type label plus the caller's selector labels."
  }

  assert {
    condition     = kubernetes_secret_v1.in_cluster.metadata[0].annotations["hashi-platform.io/vault-kms-key-alias"] == "alias/hashi-platform-dev-vault-unseal"
    error_message = "Annotations are not passed through to the cluster secret."
  }
}

run "merges_additional_values_after_defaults" {
  command = plan

  variables {
    additional_values = ["server:\n  replicas: 2\n"]
  }

  assert {
    condition     = length(helm_release.this.values) == 2 && yamldecode(helm_release.this.values[1]).server.replicas == 2
    error_message = "additional_values should be appended after the module defaults."
  }
}

run "rejects_unpinned_chart_version" {
  command = plan

  variables {
    chart_version = "10"
  }

  expect_failures = [var.chart_version]
}
