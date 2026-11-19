terraform {
  required_version = ">= 1.10"

  # Mesmo bucket de state do solidarytech-app (bucket injetado no init).
  backend "s3" {
    key          = "deploy/datadog/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.50"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Chaves no SSM (criadas uma vez, manualmente via CLI - nao gerenciadas aqui).
data "aws_ssm_parameter" "dd_api_key" {
  name            = "/solidarytech/prod/datadog/api-key"
  with_decryption = true
}

data "aws_ssm_parameter" "dd_app_key" {
  name            = "/solidarytech/prod/datadog/app-key"
  with_decryption = true
}

data "aws_ssm_parameter" "github_pat" {
  name            = "/solidarytech/prod/github/webhook-pat"
  with_decryption = true
}

provider "datadog" {
  api_key = data.aws_ssm_parameter.dd_api_key.value
  app_key = data.aws_ssm_parameter.dd_app_key.value
  api_url = "https://api.${var.datadog_site}/"
}
