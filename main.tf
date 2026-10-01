module "data_management_landing_zone" {
  source   = "./modules/data-management-landing-zone"
  for_each = var.data_management_landing_zones

  capacity_administration_members = each.value.capacity_administration_members
  capacity_name                   = each.value.capacity_name
  capacity_sku_name               = each.value.capacity_sku_name
  location                        = each.value.location
  resource_group_name             = each.value.resource_group_name
  capacity_role_assignments       = each.value.capacity_role_assignments
  enable_telemetry                = var.enable_telemetry && each.value.enable_telemetry
  lock                            = each.value.lock
  resource_group_resource_id      = each.value.resource_group_resource_id
  tags                            = merge(coalesce(var.tags, {}), each.value.tags)
}

# Mitigates, but does not eliminate, the control-plane propagation delay between an Azure
# Fabric capacity becoming visible in ARM and becoming discoverable as "Active" through the
# Fabric API. This is the same pattern used by other AVM modules for eventual-consistency
# delays (for example Azure/terraform-azurerm-avm-res-keyvault-vault's RBAC-before-contact-
# operations wait): a plain hashicorp/time time_sleep, not a local-exec polling loop. The
# postcondition below remains the actionable safety net for any propagation delay longer
# than the configured wait.
resource "time_sleep" "wait_for_capacity_activation" {
  for_each = var.data_management_landing_zones

  create_duration = var.capacity_activation_wait_duration
  triggers = {
    capacity_id = module.data_management_landing_zone[each.key].capacity_id
  }
}

data "fabric_capacity" "this" {
  for_each = var.data_management_landing_zones

  display_name = module.data_management_landing_zone[each.key].capacity_name

  lifecycle {
    postcondition {
      condition     = self.state == "Active"
      error_message = "Fabric capacity '${self.display_name}' is not yet Active in the Fabric control plane. This can happen when control-plane propagation takes longer than capacity_activation_wait_duration; re-run terraform plan/apply after a short wait, or increase capacity_activation_wait_duration, rather than adding local-exec polling."
    }
  }
  depends_on = [time_sleep.wait_for_capacity_activation]
}

module "fabric_data_landing_zone" {
  source   = "./modules/fabric-data-landing-zone"
  for_each = var.fabric_data_landing_zones

  default_capacity_id                        = data.fabric_capacity.this[each.value.capacity_key].id
  domain_description                         = each.value.domain_description
  domain_display_name                        = each.value.domain_display_name
  location                                   = var.location
  tenant_id                                  = var.tenant_id
  workspaces                                 = each.value.workspaces
  domain_role_assignments                    = each.value.domain_role_assignments
  enable_preview_domain_workspace_assignment = each.value.enable_preview_domain_workspace_assignment
  enable_preview_workspace_encryption        = each.value.enable_preview_workspace_encryption
  enable_telemetry                           = var.enable_telemetry
  tags                                       = merge(coalesce(var.tags, {}), each.value.tags)
}

module "databricks_data_landing_zone" {
  source   = "./modules/databricks-data-landing-zone"
  for_each = var.databricks_data_landing_zones

  access_connector_name                                = each.value.access_connector_name
  location                                             = each.value.location
  managed_resource_group_name                          = each.value.managed_resource_group_name
  private_subnet_name                                  = each.value.private_subnet_name
  private_subnet_network_security_group_association_id = each.value.private_subnet_network_security_group_association_id
  public_subnet_name                                   = each.value.public_subnet_name
  public_subnet_network_security_group_association_id  = each.value.public_subnet_network_security_group_association_id
  resource_group_name                                  = each.value.resource_group_name
  sku                                                  = each.value.sku
  virtual_network_id                                   = each.value.virtual_network_id
  workspace_name                                       = each.value.workspace_name
  access_connector_lock                                = each.value.access_connector_lock
  access_connector_role_assignments                    = each.value.access_connector_role_assignments
  databricks_customer_managed_keys                     = each.value.customer_managed_key
  default_storage_firewall_enabled                     = each.value.default_storage_firewall_enabled
  diagnostic_settings                                  = each.value.diagnostic_settings
  enable_telemetry                                     = var.enable_telemetry && each.value.enable_telemetry
  infrastructure_encryption_enabled                    = each.value.infrastructure_encryption_enabled
  lock                                                 = each.value.lock
  network_security_group_rules_required                = each.value.network_security_group_rules_required
  no_public_ip                                         = each.value.no_public_ip
  onelake_targets                                      = each.value.onelake_targets
  public_network_access_enabled                        = each.value.public_network_access_enabled
  resource_group_resource_id                           = each.value.resource_group_resource_id
  tags                                                 = merge(coalesce(var.tags, {}), each.value.tags)
}
