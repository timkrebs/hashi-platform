# environments/dev/platform/dev.tfvars
# Apply with: terraform plan -var-file=dev.tfvars

region = "us-east-1"

enable_cert_manager = true

# Checkmk is reachable from anywhere over HTTPS with a self-signed certificate.
# Narrow this to an office or VPN range when the sandbox becomes more than that.
enable_checkmk              = true
checkmk_instance_type       = "t3.medium"
checkmk_allowed_cidr_blocks = ["0.0.0.0/0"]
