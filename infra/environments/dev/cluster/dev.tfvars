# environments/dev/cluster/dev.tfvars
# Apply with: terraform plan -var-file=dev.tfvars

region         = "us-east-1"
vpc_cidr_block = "10.0.0.0/16"
az_count       = 3

# EKS upgrades ONE minor version per apply, and the check is against the LIVE
# cluster, not against what this file said last time. The live version is:
#
#   aws eks describe-cluster --name hashi-platform-dev-cluster \
#     --region us-east-1 --query cluster.version --output text
#
# Sequence to reach the hardened node image, one merge and one apply per row.
# Do not skip a row: setting 1.35 while the cluster is on 1.33 fails the apply
# with "Unsupported Kubernetes minor version update".
#
#   live 1.33  ->  cluster_version = "1.34", use_hardened_node_ami = false
#   live 1.34  ->  cluster_version = "1.35", use_hardened_node_ami = false
#   live 1.35  ->  cluster_version = "1.35", use_hardened_node_ami = true
#
# There is no hardened image for 1.34, so the flag stays false until 1.35.
cluster_version = "1.34"

use_hardened_node_ami = false

node_groups = {
  default = {
    instance_types = ["t3.small"]
    min_size       = 3
    max_size       = 4
    desired_size   = 3
  }
}
