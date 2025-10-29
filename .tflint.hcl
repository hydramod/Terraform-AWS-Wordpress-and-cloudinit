tflint {
  required_version = ">= 0.50"
}

config {
  call_module_type = "local"
  format           = "compact"
  disabled_by_default = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.43.0" # or whatever you pinned earlier
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_unused_declarations"       { enabled = true }
rule "terraform_deprecated_interpolation"  { enabled = true }
