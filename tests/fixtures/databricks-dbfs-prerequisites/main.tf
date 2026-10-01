# Supporting resources for the root DBFS integration test: everything a production
# deployment passes in by ID, created with AzAPI and a random suffix.
terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.12, < 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "location" {
  type        = string
  description = "Azure region for the test resources."
  nullable    = false
}

data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  numeric = true
  special = false
  upper   = false
}

locals {
  name_suffix = random_string.suffix.result
  subnets = {
    private = "10.179.1.0/24"
    public  = "10.179.0.0/24"
  }
  tags = {
    purpose = "avm-integration-test"
  }
}

resource "azapi_resource" "resource_group" {
  location  = var.location
  name      = "rg-udp-dbfs-it-${local.name_suffix}"
  parent_id = data.azapi_client_config.current.subscription_resource_id
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  tags      = local.tags
}

# Databricks adds its own network intent policy rules to this group.
resource "azapi_resource" "network_security_group" {
  location  = var.location
  name      = "nsg-udp-dbfs-it-${local.name_suffix}"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  tags      = local.tags
}

# The test starts no clusters, so the subnets need no outbound path. Production
# deployments still need explicit outbound connectivity, such as a NAT gateway.
resource "azapi_resource" "virtual_network" {
  location  = var.location
  name      = "vnet-udp-dbfs-it-${local.name_suffix}"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = ["10.179.0.0/16"]
      }
      subnets = [for name, prefix in local.subnets : {
        name = "snet-dbw-${name}"
        properties = {
          addressPrefix = prefix
          delegations = [{
            name = "databricks"
            properties = {
              serviceName = "Microsoft.Databricks/workspaces"
            }
          }]
          networkSecurityGroup = {
            id = azapi_resource.network_security_group.id
          }
        }
      }]
    }
  }
  tags = local.tags
}

# Root DBFS keys need soft delete and purge protection. Purge protection keeps the deleted
# vault for the 7-day retention period, so every run uses a new random name. Public
# access stays disabled, as many tenants enforce; Azure Storage reaches the key as a
# trusted Azure service.
resource "azapi_resource" "key_vault" {
  location  = var.location
  name      = "kv-udp-${local.name_suffix}"
  parent_id = azapi_resource.resource_group.id
  type      = "Microsoft.KeyVault/vaults@2023-07-01"
  body = {
    properties = {
      enablePurgeProtection   = true
      enableRbacAuthorization = true
      enableSoftDelete        = true
      networkAcls = {
        bypass              = "AzureServices"
        defaultAction       = "Deny"
        ipRules             = []
        virtualNetworkRules = []
      }
      publicNetworkAccess       = "Disabled"
      softDeleteRetentionInDays = 7
      sku = {
        family = "A"
        name   = "standard"
      }
      tenantId = data.azapi_client_config.current.tenant_id
    }
  }
  tags = local.tags
}

# ARM creates vault keys through PUT but cannot delete them, so the key is created by a
# resource action that is a no-op on destroy; it is removed together with its vault.
resource "azapi_resource_action" "dbfs_key" {
  method      = "PUT"
  resource_id = "${azapi_resource.key_vault.id}/keys/dbfs"
  type        = "Microsoft.KeyVault/vaults/keys@2023-07-01"
  body = {
    properties = {
      keyOps  = ["wrapKey", "unwrapKey"]
      keySize = 2048
      kty     = "RSA"
    }
  }
  response_export_values = ["properties.keyUriWithVersion"]
}

output "dbfs_key_url" {
  description = "Versioned URL of the root DBFS key."
  value       = azapi_resource_action.dbfs_key.output.properties.keyUriWithVersion
}

output "key_vault_id" {
  description = "Resource ID of the Azure RBAC Key Vault that hosts the root DBFS key."
  value       = azapi_resource.key_vault.id
}

output "location" {
  description = "Azure region of the test resources, reused for the workspace."
  value       = var.location
}

output "name_suffix" {
  description = "Random suffix shared by every test resource name."
  value       = local.name_suffix
}

output "private_subnet_id" {
  description = "Resource ID of the delegated private (container) subnet."
  value       = "${azapi_resource.virtual_network.id}/subnets/snet-dbw-private"
}

output "public_subnet_id" {
  description = "Resource ID of the delegated public (host) subnet."
  value       = "${azapi_resource.virtual_network.id}/subnets/snet-dbw-public"
}

output "resource_group_id" {
  description = "Resource ID of the test resource group."
  value       = azapi_resource.resource_group.id
}

output "resource_group_name" {
  description = "Name of the test resource group."
  value       = azapi_resource.resource_group.name
}

output "virtual_network_id" {
  description = "Resource ID of the test virtual network."
  value       = azapi_resource.virtual_network.id
}
