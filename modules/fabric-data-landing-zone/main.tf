resource "fabric_domain" "this" {
  description  = var.domain_description
  display_name = var.domain_display_name
}

resource "fabric_domain_role_assignments" "this" {
  for_each = var.domain_role_assignments

  domain_id  = fabric_domain.this.id
  principals = each.value
  role       = each.key
}

resource "fabric_workspace" "this" {
  for_each = var.workspaces

  capacity_id                    = coalesce(each.value.capacity_id, var.default_capacity_id)
  description                    = each.value.description
  display_name                   = each.value.display_name
  skip_capacity_state_validation = false
  identity = each.value.enable_workspace_identity ? {
    type = "SystemAssigned"
  } : null
}

resource "azapi_resource" "workspace_private_link_service" {
  for_each = local.private_link_workspaces

  location  = "global"
  name      = each.value.private_link_service_name
  parent_id = each.value.resource_group_resource_id
  type      = var.resource_types.fabric_private_link_services_for_fabric
  body = {
    properties = {
      tenantId    = var.tenant_id
      workspaceId = fabric_workspace.this[each.key].id
    }
  }
  ignore_body_changes       = length(var.ignore_body_changes.fabric_private_link_services_for_fabric) > 0 ? var.ignore_body_changes.fabric_private_link_services_for_fabric : null
  replace_triggers_refs     = ["properties.tenantId", "properties.workspaceId"]
  response_export_values    = []
  retry                     = var.retry
  schema_validation_enabled = false
  tags                      = var.tags

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

resource "azapi_resource" "workspace_private_endpoint" {
  for_each = local.private_link_workspaces

  location  = each.value.location
  name      = each.value.private_endpoint_name
  parent_id = each.value.resource_group_resource_id
  type      = var.resource_types.network_private_endpoints
  body = {
    properties = {
      customNetworkInterfaceName = "${each.value.private_endpoint_name}-nic"
      privateLinkServiceConnections = [{
        name = each.value.private_endpoint_name
        properties = {
          groupIds             = ["workspace"]
          privateLinkServiceId = azapi_resource.workspace_private_link_service[each.key].id
        }
      }]
      subnet = {
        id = each.value.subnet_resource_id
      }
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.network_private_endpoints) > 0 ? var.ignore_body_changes.network_private_endpoints : null
  replace_triggers_refs  = ["properties.subnet.id", "properties.privateLinkServiceConnections", "properties.customNetworkInterfaceName"]
  response_export_values = []
  retry                  = var.retry
  tags                   = var.tags

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

resource "azapi_resource" "workspace_private_dns_zone_group" {
  for_each = local.private_link_workspaces

  name      = "fabric-workspace"
  parent_id = azapi_resource.workspace_private_endpoint[each.key].id
  type      = var.resource_types.network_private_endpoints_private_dns_zone_groups
  body = {
    properties = {
      privateDnsZoneConfigs = [{
        name = "fabric"
        properties = {
          privateDnsZoneId = each.value.private_dns_zone_resource_id
        }
      }]
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.network_private_endpoints_private_dns_zone_groups) > 0 ? var.ignore_body_changes.network_private_endpoints_private_dns_zone_groups : null
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

resource "fabric_workspace_role_assignment" "this" {
  for_each = local.workspace_role_assignments

  principal    = each.value.principal
  role         = each.value.role
  workspace_id = fabric_workspace.this[each.value.workspace_key].id
}

resource "fabric_workspace_managed_private_endpoint" "this" {
  for_each = local.managed_private_endpoints

  name                            = each.value.name
  request_message                 = each.value.request_message
  target_private_link_resource_id = each.value.target_private_link_resource_id
  target_subresource_type         = each.value.target_subresource_type
  workspace_id                    = fabric_workspace.this[each.value.workspace_key].id
}

resource "fabric_workspace_outbound_cloud_connection_rules" "this" {
  for_each = local.network_restricted_workspaces

  default_action = "Deny"
  rules          = each.value.outbound_connection_rules
  workspace_id   = fabric_workspace.this[each.key].id
}

resource "fabric_workspace_outbound_gateway_rules" "this" {
  for_each = local.network_restricted_workspaces

  allowed_gateways = each.value.allowed_gateways
  default_action   = "Deny"
  workspace_id     = fabric_workspace.this[each.key].id
}

resource "fabric_workspace_git_outbound_policy" "this" {
  for_each = local.network_restricted_workspaces

  default_action = each.value.git_outbound_default_action
  workspace_id   = fabric_workspace.this[each.key].id
}

resource "fabric_workspace_network_communication_policy" "this" {
  for_each = local.network_restricted_workspaces

  workspace_id = fabric_workspace.this[each.key].id
  inbound = {
    public_access_rules = {
      default_action = each.value.private_link_ready_for_lockdown ? "Deny" : "Allow"
    }
  }
  outbound = {
    public_access_rules = {
      default_action = "Deny"
    }
  }

  depends_on = [
    fabric_workspace_managed_private_endpoint.this,
    fabric_workspace_outbound_cloud_connection_rules.this,
    fabric_workspace_outbound_gateway_rules.this,
    azapi_resource.workspace_private_link_service,
    azapi_resource.workspace_private_dns_zone_group,
  ]
}

resource "fabric_domain_workspace_assignments" "this" {
  count = var.enable_preview_domain_workspace_assignment ? 1 : 0

  domain_id     = fabric_domain.this.id
  workspace_ids = [for workspace in fabric_workspace.this : workspace.id]
}

resource "fabric_workspace_encryption" "this" {
  for_each = var.enable_preview_workspace_encryption ? {
    for key, workspace in var.workspaces : key => workspace.customer_managed_key
    if workspace.customer_managed_key != null
  } : {}

  workspace_id = fabric_workspace.this[each.key].id
  encryption_details = {
    key_identifier = each.value.key_identifier
  }
}
