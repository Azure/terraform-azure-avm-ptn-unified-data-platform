module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"
  count   = var.resource_group_resource_id == null ? 1 : 0

  location         = var.location
  name             = var.resource_group_name
  enable_telemetry = var.enable_telemetry
  tags             = var.tags
}

module "capacity" {
  source  = "Azure/avm-res-fabric-capacity/azure"
  version = "0.1.0"

  administration_members = var.capacity_administration_members
  location               = var.location
  name                   = var.capacity_name
  parent_id              = local.resource_group_resource_id
  sku_name               = var.capacity_sku_name
  enable_telemetry       = var.enable_telemetry
  lock                   = var.lock
  role_assignments       = var.capacity_role_assignments
  tags                   = var.tags
}
