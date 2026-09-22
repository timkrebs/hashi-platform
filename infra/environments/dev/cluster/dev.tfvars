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
cluster_version = "1.35"

use_hardened_node_ami = true

# t3.large statt t3.medium. Zwei Grenzen zugleich: das VPC CNI gibt einer
# t3.medium nur 17 Pods (3 ENIs x 5 + 2), einer t3.large 35 -- und der Speicher
# verdoppelt sich von 4 auf 8 GiB, was noetiger war, weil die Requests schon
# bei 60-92 Prozent lagen.
#
# max-pods muss nirgends gesetzt werden: bootstrap.sh rechnet es aus dem
# Instanztyp aus. Dass auf den t3.medium exakt 17 stand, belegt, dass die
# Berechnung greift.
#
# max_size 6 gibt der Managed Node Group Luft, Ersatz-Nodes hochzufahren,
# bevor sie die alten leert. Bei 4 liefe der Austausch strikt nacheinander.
node_groups = {
  default = {
    instance_types = ["t3.large"]
    min_size       = 3
    max_size       = 6
    desired_size   = 3
  }
}
