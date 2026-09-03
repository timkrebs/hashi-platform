# Outputs of the cluster layer, read through HCP Terraform remote state.
# The cluster workspace must share its state with this workspace.
#
# `defaults` keep `terraform validate` and early plans from failing before the
# cluster workspace has state; the Kubernetes providers then simply cannot
# connect, which is the expected outcome until the cluster exists.
data "terraform_remote_state" "cluster" {
  backend = "remote"

  config = {
    organization = "tim-krebs-org"
    workspaces = {
      name = "hashi-platform-staging"
    }
  }

  defaults = {
    account_id                         = null
    cluster_name                       = local.cluster_name
    cluster_endpoint                   = null
    cluster_certificate_authority_data = null
    oidc_provider                      = null
    oidc_provider_arn                  = null
    vpc_id                             = null
  }
}

# Short-lived Kubernetes API token signed with the run's AWS credentials. No
# aws CLI is needed, which matters on HCP Terraform workers.
data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

data "aws_caller_identity" "current" {}
