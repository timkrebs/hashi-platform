# environments/production/production.tfvars
# Apply with: terraform plan -var-file=production.tfvars

region = "us-east-1"

# Unique per environment so the VPCs can be peered later (dev uses 10.0.0.0/16).
vpc_cidr_block = "10.2.0.0/16"
az_count       = 3

cluster_version = "1.33"

# One node per availability zone as the baseline; instance size is capped at
# "medium" by the restrict-compute-size policy.
node_groups = {
  default = {
    instance_types = ["t3.medium"]
    min_size       = 2
    max_size       = 6
    desired_size   = 3
  }
}
