# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
#
# Automates the SSH-key-into-Vault-into-Boundary flow from
# docs/boundary-vault-credential-store.md. Gated behind enable_boundary_ssh.
#
# Prerequisites (see Appendix B of the runbook):
#   - the run's Vault token needs WRITE on secret/data/boundary/eks-<env>/*
#   - Boundary admin creds + an existing project scope (boundary_project_id)
#   - the periodic credential-store token (boundary_cred_store_token)
#   - hcp_boundary_cluster_id (the worker is deployed and registered here)

locals {
  boundary_ssh_enabled = var.enable_boundary_ssh ? 1 : 0
  node_ssh_secret_path = "boundary/eks-${var.environment}/node-ssh"
}

# 1. Generate an SSH key pair and register the public half as an EC2 key pair.
resource "tls_private_key" "node_ssh" {
  count     = local.boundary_ssh_enabled
  algorithm = "ED25519"
}

resource "aws_key_pair" "node_ssh" {
  count      = local.boundary_ssh_enabled
  key_name   = "eks-${var.environment}-node"
  public_key = tls_private_key.node_ssh[0].public_key_openssh
}

# 2. Store the private key in Vault for Boundary to inject. The field names match
#    what the ssh_private_key credential type expects.
resource "vault_kv_secret_v2" "node_ssh" {
  count = local.boundary_ssh_enabled
  mount = "secret"
  name  = local.node_ssh_secret_path

  data_json = jsonencode({
    username    = var.ssh_username
    private_key = tls_private_key.node_ssh[0].private_key_openssh
  })
}

# 3. Boundary credential store pointing at Vault (HCP namespace required).
resource "boundary_credential_store_vault" "eks" {
  count     = local.boundary_ssh_enabled
  name      = "vault-eks-${var.environment}"
  scope_id  = var.boundary_project_id
  address   = var.boundary_vault_address
  namespace = var.boundary_vault_namespace
  token     = var.boundary_cred_store_token
}

# 4. Credential library reading the SSH key. KV v2 path MUST include data/.
resource "boundary_credential_library_vault" "node_ssh" {
  count               = local.boundary_ssh_enabled
  name                = "node-ssh-key"
  credential_store_id = boundary_credential_store_vault.eks[0].id
  path                = "secret/data/${local.node_ssh_secret_path}"
  http_method         = "GET"
  credential_type     = "ssh_private_key"
}

# 5. SSH target with the key injected, pinned to this env's in-cluster worker.
resource "boundary_target" "node_ssh" {
  count        = local.boundary_ssh_enabled
  name         = "node-ssh"
  description  = "SSH to the EKS ${var.environment} nodes via Boundary"
  type         = "ssh"
  scope_id     = var.boundary_project_id
  default_port = 22
  address      = var.ssh_target_address

  injected_application_credential_source_ids = [
    boundary_credential_library_vault.node_ssh[0].id
  ]

  egress_worker_filter = "\"${var.environment}\" in \"/tags/env\""
}

# 6. Register a self-managed worker (controller-led). The controller mints a
#    single-use activation token the in-cluster worker reads on first boot.
resource "boundary_worker" "eks" {
  count       = local.boundary_ssh_enabled
  scope_id    = "global"
  name        = lower("${local.cluster_name}-worker")
  description = "Self-managed Boundary worker running inside the EKS cluster"
}

# 7. Deploy the worker into the cluster via the official Helm chart, tagged so
#    the target's egress filter selects it. Egress-only to HCP, so no public
#    address; auth state persists to a PVC via the EBS CSI driver.
resource "helm_release" "boundary_worker" {
  count            = local.boundary_ssh_enabled
  name             = "boundary-worker"
  namespace        = "boundary"
  create_namespace = true
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "boundary-worker"
  version          = "0.1.0"

  values = [yamlencode({
    worker = {
      config = <<-EOT
        disable_mlock           = true
        hcp_boundary_cluster_id = "${var.hcp_boundary_cluster_id}"

        listener "tcp" {
          address = "0.0.0.0:9202"
          purpose = "proxy"
        }

        listener "tcp" {
          address     = "0.0.0.0:9203"
          purpose     = "ops"
          tls_disable = true
        }

        worker {
          auth_storage_path                     = "/var/lib/boundary"
          controller_generated_activation_token = "${boundary_worker.eks[0].controller_generated_activation_token}"

          tags {
            env     = ["${var.environment}"]
            cluster = ["${local.cluster_name}"]
          }
        }
      EOT

      persistence = {
        authStorage = {
          size = "1Gi"
          path = "/var/lib/boundary"
        }
      }
    }
  })]
}
