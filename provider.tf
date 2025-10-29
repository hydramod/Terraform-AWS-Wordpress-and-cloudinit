terraform {
  required_version = "1.13.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.18.0"
    }
  }
  #Uncomment block to use remote S3 backend
  /*
  backend "s3" {
    bucket = "terraform-wp-ec2-alistechlab"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
  */
}

provider "aws" {
  region = "us-east-1"
}
