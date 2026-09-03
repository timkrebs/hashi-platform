# argocd-root-app

Creates the root Argo CD `Application` ("app of apps") that syncs a directory
of Applications and ApplicationSets from Git. It is rendered through the
[argocd-apps](https://github.com/argoproj/argo-helm/tree/main/charts/argocd-apps)
Helm chart rather than `kubernetes_manifest`, because the Application CRD does
not exist yet when this module is first planned together with the Argo CD
install.

The Application carries the `resources-finalizer.argocd.argoproj.io`
finalizer and the Helm release waits on uninstall. Together that makes
`terraform destroy` block until Argo CD has removed every child Application
and the resources they created (load balancers, volumes) before Terraform
continues with the controllers those workloads depend on. Callers should
therefore declare `depends_on` from this module to every add-on module.

## Usage

```hcl
module "argocd_root_app" {
  source = "../../../modules/argocd-root-app"

  namespace       = module.argocd.namespace
  repo_url        = "https://github.com/timkrebs/hashi-platform.git"
  target_revision = "dev"
  path            = "gitops/clusters/dev"

  depends_on = [module.argocd, module.aws_load_balancer_controller, module.cert_manager]
}
```

## Requirements

| Name      | Version           |
|-----------|-------------------|
| terraform | >= 1.9.0          |
| helm      | >= 3.0.0, < 4.0.0 |

## Inputs

| Name               | Description                                                      | Type     | Default                            | Required |
|--------------------|------------------------------------------------------------------|----------|------------------------------------|:--------:|
| repo_url           | Git repository to sync from (https, ssh or git@)                 | `string` | n/a                                | yes      |
| target_revision    | Branch, tag or commit to track                                   | `string` | n/a                                | yes      |
| path               | Directory holding the Applications/ApplicationSets to sync       | `string` | n/a                                | yes      |
| name               | Name of the root Application                                     | `string` | `"root"`                           | no       |
| namespace          | Argo CD namespace                                                | `string` | `"argocd"`                         | no       |
| project            | Argo CD project of the root Application                          | `string` | `"default"`                        | no       |
| destination_server | Cluster the child manifests are applied to                       | `string` | `"https://kubernetes.default.svc"` | no       |
| automated_sync     | Automated sync with prune and self-heal                          | `bool`   | `true`                             | no       |
| apps_chart_version | argo/argocd-apps chart version                                   | `string` | `"2.0.5"`                          | no       |
| uninstall_timeout  | Seconds Helm waits for the cascade on uninstall (60-3600)        | `number` | `600`                              | no       |

## Outputs

| Name             | Description                                   |
|------------------|-----------------------------------------------|
| application_name | Name of the root Application                  |
| release_name     | Helm release that renders it                  |
| source           | Repository, revision and path being tracked   |

## Tests

```sh
terraform init -backend=false
terraform test
```
