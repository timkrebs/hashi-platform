# Security policy

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/timkrebs/hashi-platform/security/advisories/new)
(Security tab → *Report a vulnerability*). Do not open a public issue or pull
request for anything you believe to be a security problem.

Include what you found, where (module, environment root, or workflow), how to
reproduce it, and the impact you expect. You will get an acknowledgement within
three business days and a status update at least every two weeks until the
issue is resolved. Fixes for confirmed issues are targeted within 30 days,
faster for anything that exposes credentials or allows privilege escalation.

## Scope

In scope:

- The Terraform modules under `infra/modules/`
- The environment root modules under `infra/environments/`
- The GitHub Actions workflows under `.github/workflows/`

Out of scope, please report upstream instead:

- The `terraform-aws-modules` registry modules and Terraform providers this
  repository consumes
- AWS, HCP Terraform and GitHub as services

## Supported versions

Only the current heads of the `dev`, `staging` and `production` branches are
supported. There are no tagged releases at this time.

## Handling of secrets

- No credentials, tokens or state files are stored in this repository. The
  `.gitignore` excludes state, plans and all `*.tfvars` files except the
  tracked, secret-free environment configuration files.
- Cloud credentials live in HCP Terraform variable sets; CI holds a single HCP
  Terraform team token as a GitHub secret.
- If you find a committed secret, report it as described above. It will be
  rotated and purged from history.
