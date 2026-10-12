data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  numeric = true
  special = false
  upper   = false
}

locals {
  capacity_administration_members = var.capacity_administration_members != null ? var.capacity_administration_members : toset([data.azapi_client_config.current.object_id])
  # Translates this example's flat diagnostic category-set variables into the
  # databricks-data-landing-zone module's logs/metrics/workspace_resource_id shape. Kept
  # as a local so tests/unit/defaults.tftest.hcl can assert on it directly.
  databricks_diagnostic_settings = {
    platform = {
      name                  = var.diagnostic_setting_name
      logs                  = [for category in var.diagnostic_log_categories : { category = category }]
      metrics               = [for category in var.diagnostic_metric_categories : { category = category }]
      workspace_resource_id = local.log_analytics_workspace_id
    }
  }
  databricks_subnets = {
    container = cidrsubnet(var.virtual_network_address_space, 2, 1)
    host      = cidrsubnet(var.virtual_network_address_space, 2, 0)
  }
  fabric_workspace_id        = module.unified_data_platform.workspace_ids["platform"]["platform"]
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azapi_resource.log_analytics_workspace[0].id
  tags = {
    data_classification = var.data_classification
    environment         = var.environment
    managed_by          = "terraform"
    owner               = var.owner
  }
}

# Stand-ins for the network and monitoring resources a production deployment passes in by
# resource ID, created here so the example needs no input.
resource "azapi_resource" "network_resource_group" {
  location  = var.location
  name      = "rg-udp-dbw-network-${random_string.suffix.result}"
  parent_id = data.azapi_client_config.current.subscription_resource_id
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  tags      = local.tags
}

# Databricks adds its own network intent policy rules to this group; no rules are declared
# here, so those service-managed rules never appear as drift.
resource "azapi_resource" "databricks_network_security_group" {
  location  = var.location
  name      = "nsg-udp-dbw-${random_string.suffix.result}"
  parent_id = azapi_resource.network_resource_group.id
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  tags      = local.tags
}

# Explicit outbound connectivity for secure cluster connectivity (no public IPs on
# cluster nodes); default outbound access is not available for new virtual networks.
resource "azapi_resource" "nat_public_ip" {
  location  = var.location
  name      = "pip-udp-nat-${random_string.suffix.result}"
  parent_id = azapi_resource.network_resource_group.id
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  body = {
    properties = {
      publicIPAddressVersion   = "IPv4"
      publicIPAllocationMethod = "Static"
    }
    sku = {
      name = "Standard"
    }
    zones = ["1", "2", "3"]
  }
  tags = local.tags
}

resource "azapi_resource" "nat_gateway" {
  location  = var.location
  name      = "ng-udp-dbw-${random_string.suffix.result}"
  parent_id = azapi_resource.network_resource_group.id
  type      = "Microsoft.Network/natGateways@2024-05-01"
  body = {
    properties = {
      publicIpAddresses = [{
        id = azapi_resource.nat_public_ip.id
      }]
    }
    sku = {
      name = "Standard"
    }
  }
  tags = local.tags
}

resource "azapi_resource" "virtual_network" {
  location  = var.location
  name      = "vnet-udp-dbw-${random_string.suffix.result}"
  parent_id = azapi_resource.network_resource_group.id
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = [var.virtual_network_address_space]
      }
      subnets = [for name, prefix in local.databricks_subnets : {
        name = "snet-databricks-${name}"
        properties = {
          addressPrefix = prefix
          delegations = [{
            name = "databricks"
            properties = {
              serviceName = "Microsoft.Databricks/workspaces"
            }
          }]
          natGateway = {
            id = azapi_resource.nat_gateway.id
          }
          networkSecurityGroup = {
            id = azapi_resource.databricks_network_security_group.id
          }
        }
      }]
    }
  }
  tags = local.tags
}

resource "azapi_resource" "log_analytics_workspace" {
  count = var.log_analytics_workspace_id == null ? 1 : 0

  location  = var.location
  name      = "log-udp-${random_string.suffix.result}"
  parent_id = azapi_resource.network_resource_group.id
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  body = {
    properties = {
      retentionInDays = 30
      sku = {
        name = "PerGB2018"
      }
    }
  }
  tags = local.tags
}

# The OneLake item Azure Databricks is federated with, created in the workspace the
# pattern module deploys so the example needs no existing Fabric item.
resource "fabric_lakehouse" "curated" {
  display_name = "lh_curated_${random_string.suffix.result}"
  workspace_id = local.fabric_workspace_id
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
      capacity_key        = "shared"
      domain_description  = "Business domain created by the databricks-onelake-baseline example."
      domain_display_name = "udp-dbw-${random_string.suffix.result}"
      workspaces = {
        platform = {
          description  = "Workspace created by the databricks-onelake-baseline example."
          display_name = "udp-dbw-${random_string.suffix.result}"
        }
      }
    }
  }
  location  = var.location
  tenant_id = data.azapi_client_config.current.tenant_id
  databricks_data_landing_zones = {
    platform = {
      access_connector_name                                = "ac-udp-${random_string.suffix.result}"
      diagnostic_settings                                  = local.databricks_diagnostic_settings
      location                                             = var.location
      managed_resource_group_name                          = "rg-udp-dbw-managed-${random_string.suffix.result}"
      private_subnet_name                                  = "snet-databricks-container"
      private_subnet_network_security_group_association_id = "${azapi_resource.virtual_network.id}/subnets/snet-databricks-container"
      public_network_access_enabled                        = var.public_network_access_enabled
      public_subnet_name                                   = "snet-databricks-host"
      public_subnet_network_security_group_association_id  = "${azapi_resource.virtual_network.id}/subnets/snet-databricks-host"
      resource_group_name                                  = "rg-udp-dbw-${random_string.suffix.result}"
      sku                                                  = "premium"
      virtual_network_id                                   = azapi_resource.virtual_network.id
      workspace_name                                       = "dbw-udp-${random_string.suffix.result}"
      onelake_targets = {
        curated = {
          endpoint_host       = var.onelake_endpoint_host
          fabric_item_id      = fabric_lakehouse.curated.id
          fabric_item_type    = "Lakehouse"
          fabric_workspace_id = local.fabric_workspace_id
          path                = var.onelake_path
        }
      }
    }
  }
  enable_telemetry = var.enable_telemetry
  tags             = local.tags
}
