output "access_connector_id" {
  description = "Azure resource ID of the Databricks Access Connector used for OneLake federation."
  value       = module.access_connector.resource_id
}

output "access_connector_principal_id" {
  description = "Principal ID of the Access Connector managed identity. Grant this identity access to the target Fabric workspace."
  value       = module.access_connector.system_assigned_mi_principal_id
}

output "onelake_targets" {
  description = "OneLake federation metadata and canonical ABFS URIs. Authentication and Fabric role assignment remain external prerequisites; no credentials are stored in Terraform."
  value = {
    for key, target in var.onelake_targets : key => {
      abfs_uri            = "abfss://${target.fabric_workspace_id}@${target.endpoint_host}/${target.fabric_item_id}/${target.path}"
      fabric_item_id      = target.fabric_item_id
      fabric_item_type    = target.fabric_item_type
      fabric_workspace_id = target.fabric_workspace_id
    }
  }
}

output "workspace_disk_encryption_set_id" {
  description = "Resource ID of the managed disk encryption set. Grant its identity Key Vault cryptographic permissions when managed disk CMK is enabled."
  value       = try(azapi_resource.this.output.properties.diskEncryptionSetId, null)
}

output "workspace_id" {
  description = "Azure resource ID of the Azure Databricks workspace."
  value       = azapi_resource.this.id
}

output "workspace_managed_disk_identity" {
  description = "Managed disk identity used for customer-managed key authorization."
  value = try({
    principal_id = azapi_resource.this.output.properties.managedDiskIdentity.principalId
    tenant_id    = azapi_resource.this.output.properties.managedDiskIdentity.tenantId
    type         = azapi_resource.this.output.properties.managedDiskIdentity.type
  }, null)
}

output "workspace_numeric_id" {
  description = "Azure Databricks control-plane workspace ID."
  value       = try(azapi_resource.this.output.properties.workspaceId, null)
}

output "workspace_storage_account_identity" {
  description = "Workspace storage account identity used for root DBFS customer-managed key authorization."
  value = try({
    principal_id = azapi_resource.this.output.properties.storageAccountIdentity.principalId
    tenant_id    = azapi_resource.this.output.properties.storageAccountIdentity.tenantId
    type         = azapi_resource.this.output.properties.storageAccountIdentity.type
  }, null)
}

output "workspace_url" {
  description = "Azure Databricks workspace URL."
  value       = try(azapi_resource.this.output.properties.workspaceUrl, null)
}
