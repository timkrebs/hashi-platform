# Shared TFLint configuration. CI runs `tflint --recursive --config "$(pwd)/.tflint.hcl"`
# from the repository root; locally you can run the same command.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.44.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
