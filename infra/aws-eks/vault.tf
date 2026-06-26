data "vault_kv_secret_v2" "eks" {
  mount = "secret"
  name  = "eks/config" # -> API path secret/data/eks/config in the admin/hcp-platform ns
}