output "domain_id" {
  description = "Fabric domain UUID."
  value       = fabric_domain.this.id
}

output "workspace_encryption_status" {
  description = "Fabric workspace customer-managed-key encryption status keyed by workspace key, for workspaces with customer_managed_key configured (values: Active, DisableInProgress, Disabled, EnableInProgress, Failed). Empty for workspaces without customer_managed_key or when enable_preview_workspace_encryption is false."
  value       = { for key, encryption in fabric_workspace_encryption.this : key => encryption.encryption_details.encryption_status }
}

output "workspace_identities" {
  description = "Workspace identity details keyed by workspace key. Use service_principal_id for least-privilege access to approved sources."
  value       = { for key, workspace in fabric_workspace.this : key => workspace.identity }
}

output "workspace_ids" {
  description = "Fabric workspace UUIDs keyed by the caller-supplied stable workspace keys."
  value       = { for key, workspace in fabric_workspace.this : key => workspace.id }
}

output "workspace_onelake_endpoints" {
  description = "OneLake endpoints keyed by workspace key."
  value       = { for key, workspace in fabric_workspace.this : key => workspace.onelake_endpoints }
}
