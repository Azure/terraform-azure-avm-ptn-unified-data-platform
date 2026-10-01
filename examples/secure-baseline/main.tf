data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  numeric = true
  special = false
  upper   = false
}

locals {
  capacity_administration_members = var.capacity_administration_members != null ? var.capacity_administration_members : toset([data.azapi_client_config.current.object_id])
  domain_role_assignments = {
    for role, group_id in { Admins = var.domain_administration_group_object_id } : role => [{
      id   = group_id
      type = "Group"
    }] if group_id != null
  }
  private_endpoint_subnet_name = "snet-private-endpoints"
  tags = {
    data_classification = var.data_classification
    environment         = var.environment
    managed_by          = "terraform"
    owner               = var.owner
  }
  workspace_role_assignments = {
    for key, group_id in { administrators = var.workspace_administration_group_object_id } : key => {
      principal = {
        id   = group_id
        type = "Group"
      }
      role = "Admin"
    } if group_id != null
  }
}

# Stand-ins for the ALZ connectivity resources a production deployment passes in by
# resource ID (resource group, private endpoint subnet, and the shared
# privatelink.fabric.microsoft.com zone), created here so the example needs no input.
resource "azapi_resource" "connectivity_resource_group" {
  count = var.enable_workspace_private_link ? 1 : 0

  location  = var.location
  name      = "rg-udp-connectivity-${random_string.suffix.result}"
  parent_id = data.azapi_client_config.current.subscription_resource_id
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  tags      = local.tags
}

resource "azapi_resource" "virtual_network" {
  count = var.enable_workspace_private_link ? 1 : 0

  location  = var.location
  name      = "vnet-udp-${random_string.suffix.result}"
  parent_id = azapi_resource.connectivity_resource_group[0].id
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = [var.virtual_network_address_space]
      }
      subnets = [{
        name = local.private_endpoint_subnet_name
        properties = {
          addressPrefix                  = cidrsubnet(var.virtual_network_address_space, 3, 0)
          privateEndpointNetworkPolicies = "Disabled"
        }
      }]
    }
  }
  tags = local.tags
}

resource "azapi_resource" "fabric_private_dns_zone" {
  count = var.enable_workspace_private_link ? 1 : 0

  location  = "global"
  name      = "privatelink.fabric.microsoft.com"
  parent_id = azapi_resource.connectivity_resource_group[0].id
  type      = "Microsoft.Network/privateDnsZones@2024-06-01"
  tags      = local.tags
}

resource "azapi_resource" "fabric_private_dns_zone_link" {
  count = var.enable_workspace_private_link ? 1 : 0

  location  = "global"
  name      = "vnet-udp-${random_string.suffix.result}"
  parent_id = azapi_resource.fabric_private_dns_zone[0].id
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01"
  body = {
    properties = {
      registrationEnabled = false
      virtualNetwork = {
        id = azapi_resource.virtual_network[0].id
      }
    }
  }
  tags = local.tags
}

module "unified_data_platform" {
  source = "../.."

  data_management_landing_zones = {
    shared = {
      capacity_administration_members = local.capacity_administration_members
      capacity_name                   = "fcudp${random_string.suffix.result}"
      capacity_sku_name               = "F2"
      location                        = var.location
      resource_group_name             = "rg-udp-fabric-${random_string.suffix.result}"
    }
  }
  fabric_data_landing_zones = {
    platform = {
      capacity_key                               = "shared"
      domain_description                         = "Business domain created by the secure-baseline example."
      domain_display_name                        = "udp-secure-${random_string.suffix.result}"
      enable_preview_domain_workspace_assignment = var.enable_preview_features
      domain_role_assignments                    = local.domain_role_assignments
      workspaces = {
        management = {
          description                     = "Management workspace created by the secure-baseline example."
          display_name                    = "udp-secure-${random_string.suffix.result}"
          enable_network_restrictions     = var.enable_workspace_network_restrictions
          git_outbound_default_action     = var.git_outbound_default_action
          private_link_ready_for_lockdown = var.private_link_ready_for_lockdown
          private_link = var.enable_workspace_private_link ? {
            location                     = var.location
            private_dns_zone_resource_id = azapi_resource.fabric_private_dns_zone[0].id
            private_endpoint_name        = "pe-udp-fabric-${random_string.suffix.result}"
            private_link_service_name    = "pls-udp-fabric-${random_string.suffix.result}"
            resource_group_resource_id   = azapi_resource.connectivity_resource_group[0].id
            subnet_resource_id           = "${azapi_resource.virtual_network[0].id}/subnets/${local.private_endpoint_subnet_name}"
          } : null
          role_assignments = local.workspace_role_assignments
        }
      }
    }
  }
  location         = var.location
  tenant_id        = data.azapi_client_config.current.tenant_id
  enable_telemetry = var.enable_telemetry
  tags             = local.tags
}

check "workspace_lockdown_inputs" {
  assert {
    condition     = !var.private_link_ready_for_lockdown || (var.enable_workspace_network_restrictions && var.enable_workspace_private_link)
    error_message = "private_link_ready_for_lockdown requires workspace network restrictions and workspace private link to be enabled."
  }
}
