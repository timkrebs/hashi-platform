# environments/dev/platform/dev.tfvars
# Apply with: terraform plan -var-file=dev.tfvars

region = "us-east-1"

# Sources allowed to reach the Vault API through its public load balancer.
# Starts with the environment's own VPC; add office or VPN ranges as needed.
vault_allowed_cidrs = ["10.0.0.0/16"]

enable_cert_manager = true

# Dev is ephemeral: short KMS window, and the init secret is deleted at once
# so a rebuilt environment can reuse the name.
vault_kms_key_deletion_window_in_days     = 7
vault_init_secret_recovery_window_in_days = 0
