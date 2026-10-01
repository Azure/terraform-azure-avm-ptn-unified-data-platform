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
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
  }
}
