terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.12, < 3.0"
    }
    # tflint-ignore: terraform_unused_required_providers
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
  }
}
