data "aws_partition" "current" {}

# The company's hardened EKS image. Its Kubernetes version is part of the name,
# so deriving the name from cluster_version makes it impossible for the node
# image to drift from the control plane: if no image is published for this
# version, the plan fails here rather than producing nodes that cannot join.
data "aws_ami" "hardened_node" {
  count = var.use_hardened_node_ami ? 1 : 0

  most_recent = true
  owners      = [var.node_ami_owner]

  filter {
    name   = "name"
    values = ["hc-base-ubuntu-2404-eks-${var.cluster_version}-${var.node_ami_architecture}-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  hardened_node_ami_id = one(data.aws_ami.hardened_node[*].id)

  # One flat object, not a conditional one: branching at the object level forces
  # both branches to a single type and collapses enable_bootstrap_user_data into
  # the string "true".
  #
  # ami_id is "" rather than null when the hardened image is off, because
  # upstream keys off `ami_id != ""` to decide whether a custom image is in play,
  # and null would wrongly take that path. Upstream also sets the node group's
  # ami_type to null itself once ami_id is set, letting the EKS API infer CUSTOM,
  # so ami_type stays as configured here and is simply ignored in that case.
  #
  # enable_bootstrap_user_data matters: EKS injects no bootstrap for a custom
  # image, so without it nodes launch and never join the cluster.
  node_group_ami_defaults = {
    ami_type                   = var.ami_type
    ami_id                     = var.use_hardened_node_ami ? local.hardened_node_ami_id : ""
    enable_bootstrap_user_data = var.use_hardened_node_ami
    platform                   = "linux"
  }

  node_groups = {
    for key, ng in var.node_groups : key => {
      name           = key
      instance_types = ng.instance_types
      min_size       = ng.min_size
      max_size       = ng.max_size
      desired_size   = ng.desired_size
      capacity_type  = ng.capacity_type
      labels         = ng.labels
      taints         = ng.taints

      # Deterministic role names avoid the 38-character limit that applies to
      # name prefixes and make the roles easy to find in IAM.
      iam_role_name            = "${var.cluster_name}-${key}-node"
      iam_role_use_name_prefix = false
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  iam_role_name            = "${var.cluster_name}-cluster"
  iam_role_use_name_prefix = false

  kms_key_deletion_window_in_days = var.kms_key_deletion_window_in_days

  cluster_addons = merge(var.cluster_addons, {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  })

  eks_managed_node_group_defaults = local.node_group_ami_defaults

  eks_managed_node_groups = local.node_groups

  tags = var.tags
}

# The EBS CSI driver runs as the ebs-csi-controller-sa service account and
# assumes this role through IRSA to create and attach volumes.
# https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
data "aws_iam_policy" "ebs_csi" {
  arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "${var.cluster_name}-ebs-csi"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]

  tags = var.tags
}
