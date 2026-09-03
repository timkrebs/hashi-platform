# environments/production/platform/production.tfvars
# Apply with: terraform plan -var-file=production.tfvars

region = "us-east-1"

# Sources allowed to reach the Vault API through its public load balancer.
# Starts with the environment's own VPC; add office or VPN ranges as needed.
vault_allowed_cidrs = ["10.2.0.0/16"]

enable_cert_manager = true

# Production is permanent: keep the AWS defaults so a mistaken destroy can be
# recovered within 30 days.
vault_kms_key_deletion_window_in_days     = 30
vault_init_secret_recovery_window_in_days = 30
