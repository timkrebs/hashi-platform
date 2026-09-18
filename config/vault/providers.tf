# The provider is configured against the root namespace; every resource that
# belongs to a tenant sets its own `namespace` argument. That is deliberate:
# provider aliases per namespace would multiply as namespaces are added, and
# the argument keeps the namespace visible on the resource it applies to.
provider "vault" {
  address = var.vault_address
  token   = var.vault_token

  # The cluster serves a certificate from the in-cluster cert-manager CA, which
  # no public trust store knows. Point ca_cert_file at that CA, or set
  # VAULT_CACERT on the runner. skip_tls_verify exists for a throwaway
  # environment and turns the connection into plain trust-on-first-use.
  ca_cert_file    = var.vault_ca_cert_file
  skip_tls_verify = var.vault_skip_tls_verify
}
