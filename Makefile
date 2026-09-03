# Developer entry points. `make check` mirrors the CI "Static checks" job.
SHELL := /bin/bash
.DEFAULT_GOAL := help

TFLINT_CONFIG := $(CURDIR)/.tflint.hcl
MODULE_DIRS   := $(wildcard infra/modules/*)
ENV_DIRS      := $(patsubst %/,%,$(dir $(wildcard infra/environments/*/*/main.tf)))
TF_DIRS       := $(MODULE_DIRS) $(ENV_DIRS)
ENV           ?= dev
LAYER         ?= cluster

.PHONY: help fmt fmt-check lint validate test policy-test check plan clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target> [ENV=dev] [LAYER=cluster|platform]\n\n"} /^[a-zA-Z_-]+:.*?##/ {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

fmt: ## Format all Terraform files in place
	terraform fmt -recursive infra

fmt-check: ## Fail if any Terraform file is not formatted
	terraform fmt -check -recursive -diff infra

lint: ## Run tflint on modules and environment roots
	tflint --init --config "$(TFLINT_CONFIG)"
	@for dir in $(TF_DIRS); do \
		echo "==> tflint $$dir"; \
		tflint --chdir="$$dir" --config "$(TFLINT_CONFIG)" --format compact || exit 1; \
	done

validate: ## terraform validate every module and environment root (offline)
	@for dir in $(TF_DIRS); do \
		echo "==> validate $$dir"; \
		terraform -chdir="$$dir" init -backend=false -input=false >/dev/null || exit 1; \
		terraform -chdir="$$dir" validate || exit 1; \
	done

test: ## Run the module unit tests (mocked providers, no AWS credentials)
	@for dir in $(MODULE_DIRS); do \
		echo "==> test $$dir"; \
		terraform -chdir="$$dir" init -backend=false -input=false >/dev/null || exit 1; \
		terraform -chdir="$$dir" test || exit 1; \
	done

policy-test: ## Format-check and test the Sentinel policies (needs the sentinel CLI)
	@if ! command -v sentinel >/dev/null 2>&1; then \
		echo "sentinel CLI not found; skipping policy tests (see infra/policies/README.md)"; \
	else \
		cd infra/policies && \
		sentinel fmt -check -write=false ./*.sentinel ./testdata/*.sentinel && \
		sentinel test -verbose; \
	fi

check: fmt-check lint validate test policy-test ## Everything CI runs before a plan

plan: ## Speculative plan for ENV/LAYER (default dev/cluster) against its HCP Terraform workspace
	terraform -chdir="infra/environments/$(ENV)/$(LAYER)" init -input=false
	terraform -chdir="infra/environments/$(ENV)/$(LAYER)" plan -input=false -var-file="$(ENV).tfvars"

clean: ## Remove local .terraform directories
	find infra -type d -name .terraform -prune -exec rm -rf {} +
