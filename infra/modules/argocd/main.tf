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

    # Exposed through a network load balancer when asked for. The NLB passes TCP
    # through, so argocd-server keeps terminating TLS with its own certificate;
    # no ACM certificate and therefore no domain is required.
    server = {
      resources = { requests = { cpu = "50m", memory = "128Mi" } }

      # Conditionals per attribute, not around the whole object: branches of a
      # ternary must unify to one type, and an object against {} collapses to
      # map(string), which would turn the source-range list into a string.
      service = {
        type                     = var.service_type
        loadBalancerSourceRanges = var.service_type == "LoadBalancer" ? var.load_balancer_source_ranges : []

        annotations = var.service_type == "LoadBalancer" ? {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        } : {}
      }
    }

    # Requests sized for the t3.medium node groups; limits are left to the chart.
    controller = {
      resources = { requests = { cpu = "250m", memory = "512Mi" } }
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
