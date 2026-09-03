# Contributing to hashi-platform

Thanks for taking the time to contribute. This document explains how the
repository is organised, how changes flow through it, and what a pull request
needs before it can be merged.

## Ways to contribute

- Report bugs or unexpected plans through a
  [bug report](https://github.com/timkrebs/hashi-platform/issues/new?template=bug_report.yml).
- Propose module features or new environments through a
  [feature request](https://github.com/timkrebs/hashi-platform/issues/new?template=feature_request.yml).
- Improve documentation, tests or the pipeline.

For anything larger than a small fix, open an issue first so the approach can
be agreed before you invest time in it.

## Development setup

You need:

- Terraform 1.16.x (`brew install terraform` or [tenv](https://github.com/tofuutils/tenv))
- [tflint](https://github.com/terraform-linters/tflint) 0.61 or newer
- [pre-commit](https://pre-commit.com) (optional but recommended)
- [actionlint](https://github.com/rhysd/actionlint) if you touch workflows

Then:

```sh
git clone https://github.com/timkrebs/hashi-platform.git
cd hashi-platform
pre-commit install
make check
```

`make check` runs the same steps as the CI `Static checks` job: `terraform fmt
-check`, `tflint`, `terraform validate` for every module and environment root,
and the module unit tests. Run `make help` to see the individual targets.

Planning against a real workspace requires `terraform login` and access to the
`tim-krebs-org` organisation in HCP Terraform. AWS credentials are not needed
locally; runs execute remotely.

## Branching model

| Branch       | Purpose                                             |
|--------------|-----------------------------------------------------|
| `dev`        | Integration branch. All feature work lands here.    |
| `staging`    | Promotion target from `dev`.                        |
| `production` | Promotion target from `staging`.                    |

1. Branch from `dev`: `git switch -c feat/aws-eks-cluster-spot-groups dev`.
2. Open a pull request into `dev`. CI runs the static checks and posts a
   speculative plan for the dev environment on the PR.
3. After review and merge, CI plans and applies to the dev workspace.
4. Maintainers promote by opening pull requests `dev → staging` and
   `staging → production`. Those applies wait for the reviewers configured on
   the GitHub environment.

Never push directly to the three environment branches.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) with the
module or environment as scope:

```
feat(aws-eks-cluster): support spot capacity in node groups
fix(aws-vpc): reject subnet prefixes smaller than the VPC allows
docs(infra): describe how to add an environment
ci: pin tflint to 0.61
```

Types in use: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`.

## Standards for Terraform changes

- Follow the [HashiCorp style conventions](https://developer.hashicorp.com/terraform/language/style):
  two-space indentation, `terraform fmt`, snake_case names, one resource type
  per logical block, meta-arguments first.
- Every variable and output has a `description` and every variable a `type`.
  Add `validation` blocks for anything a user can get wrong.
- Modules stay provider-agnostic in structure: no `provider` blocks inside
  modules, versions declared in `versions.tf` as lower bounds.
- Do not reference one module from another. Dependencies flow through the
  root module.
- Pin upstream registry modules to exact versions inside the modules and note
  bumps in the changelog.
- Every module change comes with a unit test in `tests/` and an update to the
  module README (inputs, outputs, examples).
- Never commit credentials, account identifiers or state. Environment
  `<name>.tfvars` files are tracked on purpose and must stay free of secrets.

## Pull request checklist

Before you mark a pull request ready for review:

- [ ] `make check` passes locally.
- [ ] The plan posted on the pull request shows only the changes you intend,
      and no unexpected destroys or replacements.
- [ ] Module READMEs and `infra/README.md` reflect the change.
- [ ] `CHANGELOG.md` has an entry under **Unreleased**.
- [ ] Workflow changes pass `actionlint`.

Pull requests are squash-merged. The `Static checks` and `Plan <environment>`
status checks are required on all three environment branches.

## Adding a new environment

Follow the steps in the [infra README](infra/README.md#adding-an-environment).
A new environment touches the HCP Terraform organisation, GitHub environments
and both workflows, so coordinate it with a maintainer first.

## Reporting security issues

Please do not open public issues for security problems. Follow
[SECURITY.md](SECURITY.md).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By
participating you agree to uphold it.
