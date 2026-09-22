# Config for the sentinel CLI only. Vault does not read this file -- the EGP is
# deployed by config/vault/egp.tf, which sets the enforcement level.
policy "kv-naming" {
  source = "./kv-naming.sentinel"
}

policy "business-hrs" {
  source = "./business-hrs.sentinel"
}
