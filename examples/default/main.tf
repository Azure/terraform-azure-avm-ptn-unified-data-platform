data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  numeric = true
  special = false
  upper   = false
}

locals {
  capacity_administration_members = var.capacity_administration_members != null ? var.capacity_administration_members : toset([data.azapi_client_config.current.object_id])
}

module "unified_data_platform" {
  source = "../.."

  data_management_landing_zones = {
    shared = {
      capacity_administration_members = local.capacity_administration_members
      capacity_name                   = "fcudp${random_string.suffix.result}"
      capacity_sku_name               = "F2"
      location                        = var.location
      resource_group_name             = "rg-udp-default-${random_string.suffix.result}"
    }
  }
  fabric_data_landing_zones = {
    platform = {
      capacity_key        = "shared"
      domain_description  = "Business domain created by the default example."
      domain_display_name = "udp-default-${random_string.suffix.result}"
      workspaces = {
        platform = {
          description  = "Workspace created by the default example."
          display_name = "udp-default-${random_string.suffix.result}"
        }
      }
    }
  }
  location         = var.location
  tenant_id        = data.azapi_client_config.current.tenant_id
  enable_telemetry = var.enable_telemetry
}
