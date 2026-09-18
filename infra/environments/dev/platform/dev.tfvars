# environments/dev/platform/dev.tfvars
# Apply with: terraform plan -var-file=dev.tfvars

region = "us-east-1"

enable_cert_manager = true


# Argo CD plus the AWS resources Vault needs. Vault itself is deployed from
# gitops/, not from here.
enable_argocd              = true
enable_vault_prerequisites = true

# Dev is ephemeral: shortest KMS window, and the init secret is deleted at once
# so a rebuilt environment can reuse the name.
vault_kms_key_deletion_window_in_days     = 7
vault_init_secret_recovery_window_in_days = 0

# Argo CD UI oeffentlich erreichbar. Auf Office-/VPN-Bereiche einschraenken,
# sobald das mehr als eine Sandbox ist.
argocd_service_type        = "LoadBalancer"
argocd_allowed_cidr_blocks = ["0.0.0.0/0"]

# Container-Logs zusaetzlich nach CloudWatch als dauerhaftes Archiv.
# Interaktive Suche laeuft ueber Loki im Cluster.
enable_log_shipping   = true
log_retention_in_days = 14
