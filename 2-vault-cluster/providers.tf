# hcp authenticates via the workspace's OIDC dynamic credentials (TFC_HCP_*
# env vars from 0-bootstrap); the project is inferred from the project-scoped
# service principal. tfe reuses the run's own API token to read the
# 1-network workspace outputs — no extra credentials anywhere.

provider "hcp" {}

provider "tfe" {}
