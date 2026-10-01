output "capacity_id" {
  description = "Azure resource ID of the Fabric capacity."
  value       = module.capacity.resource_id
}

output "capacity_name" {
  description = "Name of the Fabric capacity."
  value       = module.capacity.name
}

output "resource_group_id" {
  description = "Resource ID of the resource group that contains the Fabric capacity."
  value       = local.resource_group_resource_id
}
