# Makefile for hashi-platform
#
# Run `make check` before every commit and push. It runs the same static
# checks the CI pipeline enforces, so failures are caught locally first.

SHELL  := /bin/bash
TF_DIR := infra/aws-eks

.DEFAULT_GOAL := help

.PHONY: help
help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

.PHONY: check
check: fmt-check validate yaml ascii ## Run all pre-commit checks (use this before commit/push)
	@echo "OK: all checks passed."

.PHONY: fmt
fmt: ## Format all Terraform files in place
	terraform fmt -recursive

.PHONY: fmt-check
fmt-check: ## Verify Terraform formatting without modifying files
	terraform fmt -check -recursive

.PHONY: validate
validate: ## Initialize (no backend) and validate the Terraform config
	cd $(TF_DIR) && terraform init -backend=false -input=false >/dev/null && terraform validate

.PHONY: lint
lint: ## Run tflint if installed (skipped otherwise)
	@if command -v tflint >/dev/null 2>&1; then \
		cd $(TF_DIR) && tflint; \
	else \
		echo "tflint not installed; skipping"; \
	fi

.PHONY: yaml
yaml: ## Validate GitHub Actions workflow YAML
	@python3 -c "import yaml, glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]; print('OK: workflow YAML is valid')"

.PHONY: ascii
ascii: ## Fail if any source file contains non-ASCII characters (no emojis)
	@matches=$$(LC_ALL=C grep -rn '[^[:print:][:space:]]' \
		--include='*.md' --include='*.yml' --include='*.yaml' \
		--include='*.tf' --include='*.sh' --include='*.hcl' \
		--include='*.example' --include='Makefile' \
		--exclude-dir=.terraform . | grep -v '^\./LICENSE' || true); \
	if [ -n "$$matches" ]; then \
		echo "ERROR: non-ASCII characters found:"; echo "$$matches"; exit 1; \
	else \
		echo "OK: no non-ASCII characters"; \
	fi

.PHONY: clean
clean: ## Remove local Terraform working directories
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
