resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "this" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.this.metadata[0].name

  values = concat([yamlencode({
    crds = {
      keep = false
    }

    dex = {
      enabled = false
    }

    notifications = {
      enabled = false
    }

    configs = {
      params = {
        "server.insecure" = var.server_insecure
      }
    }

    # Requests sized for the t3.medium node groups; limits are left to the chart.
    controller = {
      resources = { requests = { cpu = "250m", memory = "512Mi" } }
    }
    server = {
      resources = { requests = { cpu = "50m", memory = "128Mi" } }
    }
    repoServer = {
      resources = { requests = { cpu = "100m", memory = "256Mi" } }
    }
    applicationSet = {
      resources = { requests = { cpu = "50m", memory = "128Mi" } }
    }
    redis = {
      resources = { requests = { cpu = "50m", memory = "64Mi" } }
    }
  })], var.additional_values)

  wait    = true
  timeout = 600
}

# Explicit registration of the local cluster. Argo CD treats the in-cluster
# target as implicit, but only a Secret gives it labels (for ApplicationSet
# selectors) and annotations (the Terraform -> GitOps bridge).
resource "kubernetes_secret_v1" "in_cluster" {
  metadata {
    name      = "cluster-in-cluster"
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    labels = merge(
      { "argocd.argoproj.io/secret-type" = "cluster" },
      var.cluster_secret_labels,
    )

    annotations = var.cluster_secret_annotations
  }

  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }

  type = "Opaque"
}
