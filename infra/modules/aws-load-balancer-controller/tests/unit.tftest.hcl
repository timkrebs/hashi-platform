# Unit tests: plan mode with mocked providers; the upstream IRSA module is
# replaced by fixed outputs. No AWS or cluster access needed.
#
#   cd infra/modules/aws-load-balancer-controller && terraform init -backend=false && terraform test

mock_provider "aws" {}
mock_provider "helm" {}

override_module {
  target = module.irsa
  outputs = {
    iam_role_arn  = "arn:aws:iam::123456789012:role/unit-test-alb-controller"
    iam_role_name = "unit-test-alb-controller"
  }
}

variables {
  cluster_name      = "unit-test"
  region            = "us-east-1"
  vpc_id            = "vpc-0123456789abcdef0"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0123456789ABCDEF"
}

run "wires_cluster_and_irsa_role_into_chart_values" {
  command = plan

  assert {
    condition     = output.iam_role_arn == "arn:aws:iam::123456789012:role/unit-test-alb-controller"
    error_message = "iam_role_arn is not passed through from the IRSA module."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).clusterName == "unit-test" && yamldecode(helm_release.this.values[0]).vpcId == "vpc-0123456789abcdef0"
    error_message = "Chart values do not carry the cluster name and VPC."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).serviceAccount.annotations["eks.amazonaws.com/role-arn"] == "arn:aws:iam::123456789012:role/unit-test-alb-controller"
    error_message = "Service account is not annotated with the IRSA role."
  }

  assert {
    condition     = helm_release.this.namespace == "kube-system" && helm_release.this.version == "3.5.0" && helm_release.this.wait == true
    error_message = "Release should install the pinned chart into kube-system and wait for readiness."
  }
}

run "rejects_unpinned_chart_version" {
  command = plan

  variables {
    chart_version = "latest"
  }

  expect_failures = [var.chart_version]
}

run "rejects_zero_replicas" {
  command = plan

  variables {
    replica_count = 0
  }

  expect_failures = [var.replica_count]
}
