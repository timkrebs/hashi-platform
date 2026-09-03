provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = local.cluster.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster.cluster_endpoint
    cluster_ca_certificate = local.cluster_ca_certificate
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
