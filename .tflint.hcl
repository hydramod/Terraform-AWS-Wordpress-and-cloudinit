config {
  module = true
}

plugin "aws" {
  enabled = true
  version = "0.43.0" # bump as needed
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_unused_declarations" { enabled = true }
rule "terraform_deprecated_interpolation" { enabled = true }
