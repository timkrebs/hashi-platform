# environments/dev/cluster/dev.tfvars
# Apply with: terraform plan -var-file=dev.tfvars

region         = "us-east-1"
vpc_cidr_block = "10.0.0.0/16"
az_count       = 3

# Upgrading to 1.35, where the hardened EKS image is published. EKS only moves
# one minor version per apply, so this goes 1.33 -> 1.34 -> 1.35; see the
# "Hardened node images" section of infra/README.md for the sequence.
cluster_version = "1.35"

# Turn on only once cluster_version is "1.35". There is no hardened image for
# 1.34, so the nodes stay on AL2023 while passing through it.
use_hardened_node_ami = true

node_groups = {
  default = {
    instance_types = ["t3.small"]
    min_size       = 1
    max_size       = 3
    desired_size   = 2
  }
}
