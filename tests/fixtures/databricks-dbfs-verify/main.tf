# Reads the deployed workspace and its root DBFS storage account back from Azure, so the
# integration test checks the live encryption state rather than the planned request.
terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.12, < 3.0"
    }
  }
}

variable "workspace_id" {
  type        = string
  description = "Resource ID of the Azure Databricks workspace under test."
  nullable    = false
}

data "azapi_resource" "workspace" {
  resource_id            = var.workspace_id
  type                   = "Microsoft.Databricks/workspaces@2026-01-01"
  response_export_values = ["properties.managedResourceGroupId", "properties.parameters.encryption", "properties.parameters.storageAccountName"]
}

# The root DBFS storage account lives in the Databricks-managed resource group, which
# allows reads despite its deny assignment.
data "azapi_resource" "dbfs_storage_account" {
  name                   = data.azapi_resource.workspace.output.properties.parameters.storageAccountName.value
  parent_id              = data.azapi_resource.workspace.output.properties.managedResourceGroupId
  type                   = "Microsoft.Storage/storageAccounts@2023-05-01"
  response_export_values = ["properties.encryption"]
}

output "storage_key_name" {
  description = "Key name the root DBFS storage account encrypts with, lowercased."
  value       = lower(try(data.azapi_resource.dbfs_storage_account.output.properties.encryption.keyvaultproperties.keyname, ""))
}

output "storage_key_source" {
  description = "Encryption key source of the root DBFS storage account, lowercased."
  value       = lower(try(data.azapi_resource.dbfs_storage_account.output.properties.encryption.keySource, ""))
}

output "workspace_key_name" {
  description = "Root DBFS key name the workspace reports, lowercased."
  value       = lower(try(data.azapi_resource.workspace.output.properties.parameters.encryption.value.KeyName, ""))
}

output "workspace_key_source" {
  description = "Root DBFS key source the workspace reports, lowercased."
  value       = lower(try(data.azapi_resource.workspace.output.properties.parameters.encryption.value.keySource, ""))
}
