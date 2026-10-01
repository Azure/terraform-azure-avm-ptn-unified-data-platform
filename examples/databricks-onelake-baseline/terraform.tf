terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.12, < 3.0"
    }
    fabric = {
      source  = "microsoft/fabric"
      version = ">= 1.14, < 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "fabric" {
  tenant_id = data.azapi_client_config.current.tenant_id
}
