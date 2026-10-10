output "capacity_resource_ids" {
  description = "Azure Fabric capacity ARM resource IDs keyed by data management landing zone key."
  value       = { for key, zone in module.data_management_landing_zone : key => zone.capacity_id }
}

output "databricks_data_landing_zones" {
  description = "Azure Databricks workspace, managed identity, and OneLake integration outputs keyed by landing-zone key."
  value = {
    for key, zone in module.databricks_data_landing_zone : key => {
      access_connector_id                = zone.access_connector_id
      access_connector_principal_id      = zone.access_connector_principal_id
      onelake_targets                    = zone.onelake_targets
      workspace_disk_encryption_set_id   = zone.workspace_disk_encryption_set_id
      workspace_id                       = zone.workspace_id
      workspace_managed_disk_identity    = zone.workspace_managed_disk_identity
      workspace_numeric_id               = zone.workspace_numeric_id
      workspace_storage_account_identity = zone.workspace_storage_account_identity
      workspace_url                      = zone.workspace_url
    }
  }
}

output "domain_ids" {
  description = "Fabric domain UUIDs keyed by data landing zone key."
  value       = { for key, zone in module.fabric_data_landing_zone : key => zone.domain_id }
}

output "fabric_capacity_ids" {
  description = "Fabric capacity UUIDs keyed by data management landing zone key."
  value       = { for key, capacity in data.fabric_capacity.this : key => capacity.id }
}

output "workspace_encryption_status" {
  description = "Fabric workspace customer-managed-key encryption status maps keyed first by data landing zone and then by workspace key, for workspaces with customer_managed_key configured."
  value       = { for key, zone in module.fabric_data_landing_zone : key => zone.workspace_encryption_status }
}

output "workspace_identities" {
  description = "Fabric workspace identities keyed first by data landing zone and then by workspace key."
  value       = { for key, zone in module.fabric_data_landing_zone : key => zone.workspace_identities }
}

output "workspace_ids" {
  description = "Fabric workspace UUID maps keyed first by data landing zone and then by workspace key."
  value       = { for key, zone in module.fabric_data_landing_zone : key => zone.workspace_ids }
}

output "workspace_onelake_endpoints" {
  description = "Fabric workspace OneLake endpoint maps keyed first by data landing zone and then by workspace key."
  value       = { for key, zone in module.fabric_data_landing_zone : key => zone.workspace_onelake_endpoints }
}
