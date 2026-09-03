# environments/staging/cluster/staging.tfvars
# Apply with: terraform plan -var-file=staging.tfvars

region         = "us-east-1"
vpc_cidr_block = "10.1.0.0/16"
az_count       = 3

cluster_version = "1.33"

node_groups = {
  default = {
    instance_types = ["t3.small"]
    min_size       = 1
    max_size       = 3
    desired_size   = 2
  }
}
