# environments/dev/platform/dev.tfvars
# Apply with: terraform plan -var-file=dev.tfvars

region = "us-east-1"

enable_cert_manager = true

# Checkmk is reachable from anywhere over HTTPS with a self-signed certificate.
# Narrow this to an office or VPN range when the sandbox becomes more than that.
enable_checkmk              = true
checkmk_instance_type       = "t3.medium"
checkmk_allowed_cidr_blocks = ["0.0.0.0/0"]

# Argo CD plus the AWS resources Vault needs. Vault itself is deployed from
# gitops/, not from here.
enable_argocd              = true
enable_vault_prerequisites = true

# Dev is ephemeral: shortest KMS window, and the init secret is deleted at once
# so a rebuilt environment can reuse the name.
vault_kms_key_deletion_window_in_days     = 7
vault_init_secret_recovery_window_in_days = 0
