resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "this" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.this.metadata[0].name

  values = [yamlencode({
    crds = {
      enabled = true
      keep    = var.keep_crds_on_uninstall
    }

    resources = {
      requests = {
        cpu    = "25m"
        memory = "64Mi"
      }
    }

    webhook = {
      resources = {
        requests = {
          cpu    = "10m"
          memory = "32Mi"
        }
      }
    }

    cainjector = {
      resources = {
        requests = {
          cpu    = "10m"
          memory = "64Mi"
        }
      }
    }
  })]

  wait    = true
  timeout = 300
}
