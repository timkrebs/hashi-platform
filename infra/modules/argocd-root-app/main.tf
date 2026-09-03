# The root Application ("app of apps") is rendered through the argocd-apps
# chart rather than kubernetes_manifest, because the Application CRD does not
# exist yet when this module is first planned alongside the Argo CD install.
#
# With the resources finalizer, deleting the root Application cascades to
# every child Application and their resources. Helm waits for that deletion
# on uninstall, so `terraform destroy` blocks here until Argo CD has removed
# the workloads (and the AWS objects they created) before the add-ons they
# rely on are uninstalled.
resource "helm_release" "this" {
  name       = "argocd-${var.name}"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.apps_chart_version
  namespace  = var.namespace

  values = [yamlencode({
    applications = {
      (var.name) = {
        namespace  = var.namespace
        project    = var.project
        finalizers = ["resources-finalizer.argocd.argoproj.io"]

        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = var.path
          directory = {
            recurse = true
          }
        }

        destination = {
          server    = var.destination_server
          namespace = var.namespace
        }

        syncPolicy = merge(
          var.automated_sync ? {
            automated = {
              prune    = true
              selfHeal = true
            }
          } : {},
          {
            syncOptions = ["CreateNamespace=true"]
          },
        )
      }
    }
  })]

  wait    = true
  timeout = var.uninstall_timeout
}
