# Authenticates per-run via OIDC dynamic credentials (TFC_HCP_* env vars from
# the project-wide variable set managed in 0-bootstrap). No stored secret.
provider "hcp" {}
