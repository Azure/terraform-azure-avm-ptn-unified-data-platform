module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"
  count   = var.resource_group_resource_id == null ? 1 : 0

  location         = var.location
  name             = var.resource_group_name
  enable_telemetry = var.enable_telemetry
  retry            = var.retry
  tags             = var.tags
  timeouts         = var.timeouts
}

module "access_connector" {
  source  = "Azure/avm-res-databricks-accessconnector/azurerm"
  version = "0.1.0"

  location            = var.location
  name                = var.access_connector_name
  parent_id           = local.resource_group_resource_id
  enable_telemetry    = var.enable_telemetry
  ignore_body_changes = var.ignore_body_changes.databricks_access_connectors
  lock                = var.access_connector_lock
  managed_identities  = { system_assigned = true }
  resource_types      = var.resource_types.databricks_access_connectors
  retry               = var.retry
  role_assignments    = var.access_connector_role_assignments
  tags                = var.tags
  timeouts            = var.timeouts
}

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.workspace_name
  parent_id = local.resource_group_resource_id
  type      = var.resource_types.databricks_workspaces
  body = {
    sku        = { name = var.sku }
    properties = local.workspace_properties
  }
  ignore_body_changes = length(var.ignore_body_changes.databricks_workspaces) > 0 ? var.ignore_body_changes.databricks_workspaces : null
  # Preserve AVM 0.5.0's omission when false without an absent-to-false migration
  # replacement. Subsequent changes still replace this create-only storage setting.
  replace_triggers_external_values = {
    infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  }
  replace_triggers_refs = [
    "properties.managedResourceGroupId",
    "properties.parameters.customVirtualNetworkId.value",
    "properties.parameters.customPublicSubnetName.value",
    "properties.parameters.customPrivateSubnetName.value",
  ]
  response_export_values = [
    "properties.workspaceId",
    "properties.workspaceUrl",
    "properties.managedResourceGroupId",
    "properties.diskEncryptionSetId",
    "properties.managedDiskIdentity",
    "properties.storageAccountIdentity",
  ]
  retry = var.retry
  tags  = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  lifecycle {
    # Referencing the caller's association IDs also preserves the dependency on NSG
    # association completion before VNet-injected workspace creation.
    precondition {
      condition     = lower(var.private_subnet_network_security_group_association_id) == lower("${var.virtual_network_id}/subnets/${var.private_subnet_name}")
      error_message = "private_subnet_network_security_group_association_id must identify the private subnet used for workspace VNet injection."
    }
    precondition {
      condition     = lower(var.public_subnet_network_security_group_association_id) == lower("${var.virtual_network_id}/subnets/${var.public_subnet_name}")
      error_message = "public_subnet_network_security_group_association_id must identify the public subnet used for workspace VNet injection."
    }
  }
}

# Databricks creates the workspace storage identity only when the workspace is prepared for
# encryption, and Microsoft's documented order grants that identity access to the key
# before the key is bound. This opt-in grant sits between those steps, so one apply can
# create, grant and bind. The identity is unknown during every workspace update, so the
# body stays as created; a planned workspace replacement (the ID becomes unknown only
# then) replaces the grant for the new identity, because ARM rejects changing it in place.
resource "azapi_resource" "dbfs_root_key_role_assignment" {
  count = local.dbfs_root_key_role_assignment == null ? 0 : 1

  name      = uuidv5("url", "${lower(local.resource_group_resource_id)}/providers/microsoft.databricks/workspaces/${lower(var.workspace_name)}/dbfs-root-key/${lower(local.dbfs_root_key_role_assignment_scope)}")
  parent_id = local.dbfs_root_key_role_assignment_scope
  type      = var.resource_types.authorization_role_assignments
  body = {
    properties = {
      description      = "Lets the Azure Databricks workspace storage account use its root DBFS customer-managed key."
      principalId      = azapi_resource.this.output.properties.storageAccountIdentity.principalId
      principalType    = "ServicePrincipal"
      roleDefinitionId = local.dbfs_root_key_role_definition_id
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.authorization_role_assignments) > 0 ? var.ignore_body_changes.authorization_role_assignments : null
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  lifecycle {
    ignore_changes       = [body]
    replace_triggered_by = [azapi_resource.this.id]
  }
}

# Changes only when the DBFS key grant is created, removed or moved to another key or
# vault, so the binding below runs again in the same apply. The indirection exists because
# replace_triggered_by rejects a resource with no instances.
resource "terraform_data" "dbfs_root_key_grant_revision" {
  input = try(azapi_resource.dbfs_root_key_role_assignment[0].name, null)
}

# Root DBFS encryption must be bound after prepareEncryption has created the storage
# identity. Keep this node even without a key: removal of a key updates it to Default,
# matching AzureRM's revert operation instead of azapi_update_resource's no-op delete.
# Workspace updates omit parameters.encryption, which the service treats as keeping the
# current binding (the integration test checks this after a workspace update). AzAPI
# 2.12/2.13 do not expose ignore_body_changes on azapi_update_resource. A replaced
# workspace starts with platform-managed keys, so it is bound again.
resource "azapi_update_resource" "dbfs_root_key" {
  resource_id = azapi_resource.this.id
  type        = var.resource_types.databricks_workspaces
  body = {
    properties = {
      parameters = {
        encryption = { value = local.dbfs_root_encryption }
      }
    }
  }
  response_export_values = []
  retry                  = local.dbfs_root_key_retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  lifecycle {
    replace_triggered_by = [azapi_resource.this.id, terraform_data.dbfs_root_key_grant_revision]
  }
  depends_on = [azapi_resource.dbfs_root_key_role_assignment]
}

resource "azapi_resource" "lock" {
  count = var.lock == null ? 0 : 1

  name      = coalesce(var.lock.name, "lock-${var.lock.kind}")
  parent_id = azapi_resource.this.id
  type      = var.resource_types.authorization_locks
  body = {
    properties = {
      level = var.lock.kind
      notes = coalesce(var.lock.notes, var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources.")
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.authorization_locks) > 0 ? var.ignore_body_changes.authorization_locks : null
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }

  depends_on = [azapi_update_resource.dbfs_root_key, azapi_resource.diagnostic_settings]
}

# Normalize the utility's AzureDiagnostics literal after its optional-attribute defaults
# have been applied, so ARM receives null without a second conversion to Dedicated.
module "diagnostic_settings_interface" {
  source  = "Azure/avm-utl-interfaces/azure"
  version = "0.7.0"

  diagnostic_settings_v2 = var.diagnostic_settings
  enable_telemetry       = var.enable_telemetry
}

data "azapi_resource_list" "diagnostic_categories" {
  count = anytrue([for setting in var.diagnostic_settings : alltrue([for log in setting.logs : log.category_group == null])]) ? 1 : 0

  parent_id = azapi_resource.this.id
  type      = "Microsoft.Insights/diagnosticSettingsCategories@2021-05-01-preview"
  response_export_values = {
    log_categories = "value[?properties.categoryType == 'Logs'].name"
  }
  retry = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      read = timeouts.value.read
    }
  }
}

resource "azapi_resource" "diagnostic_settings" {
  for_each = module.diagnostic_settings_interface.diagnostic_settings_azapi_v2

  name      = local.diagnostic_setting_names[each.key]
  parent_id = azapi_resource.this.id
  type      = var.resource_types.insights_diagnostic_settings
  body = merge(each.value.body, {
    properties = merge(each.value.body.properties, {
      logAnalyticsDestinationType = var.diagnostic_settings[each.key].log_analytics_destination_type == "AzureDiagnostics" ? null : "Dedicated"
      logs                        = local.diagnostic_setting_logs[each.key]
      metrics                     = coalesce(each.value.body.properties.metrics, [])
    })
  })
  ignore_body_changes = length(var.ignore_body_changes.insights_diagnostic_settings) > 0 ? var.ignore_body_changes.insights_diagnostic_settings : null
  list_unique_id_property = {
    "properties.logs"    = "category, categoryGroup"
    "properties.metrics" = "category"
  }
  response_export_values = []
  retry                  = var.retry

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      delete = timeouts.value.delete
      read   = timeouts.value.read
      update = timeouts.value.update
    }
  }
}

moved {
  from = module.workspace.azapi_resource.this
  to   = azapi_resource.this
}

# AzAPI's azapi_resource MoveState accepts AzureRM ARM IDs, including management locks.
moved {
  from = module.workspace.azurerm_management_lock.this[0]
  to   = azapi_resource.lock[0]
}

# azapi_update_resource has no cross-provider MoveState support. Forget only the old
# binding; its workspace remains managed above and the new update node adopts the key.
# Terraform needs a configured AzureRM provider to process this block, so roots without
# one remove the binding from state first (docs/deployment.md, section 8).
removed {
  from = module.workspace.azurerm_databricks_workspace_root_dbfs_customer_managed_key.this

  lifecycle {
    destroy = false
  }
}
