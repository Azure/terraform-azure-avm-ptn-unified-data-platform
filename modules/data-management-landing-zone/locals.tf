locals {
  resource_group_resource_id = var.resource_group_resource_id == null ? module.resource_group[0].resource_id : var.resource_group_resource_id
}
