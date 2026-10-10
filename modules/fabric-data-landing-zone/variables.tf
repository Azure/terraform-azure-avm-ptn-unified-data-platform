variable "default_capacity_id" {
  type        = string
  description = "Fabric capacity UUID used by workspaces that don't specify capacity_id. Obtain it from the Fabric API or fabric_capacity data source; this is not the Azure ARM resource ID."
  nullable    = false
}

variable "domain_description" {
  type        = string
  description = "Business purpose, ownership boundary, and expected data products for the Fabric domain."
  nullable    = false
}

variable "domain_display_name" {
  type        = string
  description = "Display name of the Fabric business domain."
  nullable    = false
}

variable "location" {
  type        = string
  description = "Azure region for module telemetry (SFR4). Private endpoints retain their independently supplied private_link.location."
  nullable    = false
}

variable "tenant_id" {
  type        = string
  description = "Microsoft Entra tenant ID used only when a workspace-level private link service is requested."
  nullable    = false
}

variable "workspaces" {
  type = map(object({
    display_name                = string
    description                 = string
    capacity_id                 = optional(string)
    enable_workspace_identity   = optional(bool, true)
    enable_network_restrictions = optional(bool, false)
    git_outbound_default_action = optional(string, "Allow")
    private_link = optional(object({
      location                     = string
      private_dns_zone_resource_id = string
      private_endpoint_name        = string
      private_link_service_name    = string
      resource_group_resource_id   = string
      subnet_resource_id           = string
      tags                         = optional(map(string), {})
    }))
    private_link_ready_for_lockdown = optional(bool, false)
    customer_managed_key = optional(object({
      key_identifier = string
    }))
    role_assignments = optional(map(object({
      principal = object({
        id   = string
        type = string
      })
      role = string
    })), {})
    managed_private_endpoints = optional(map(object({
      name                            = string
      target_private_link_resource_id = string
      target_subresource_type         = optional(string)
      request_message                 = optional(string, "Requested by the Fabric landing zone Terraform module.")
    })), {})
    outbound_connection_rules = optional(set(object({
      connection_type = string
      default_action  = string
      allowed_endpoints = optional(set(object({
        hostname_pattern = string
      })), [])
      allowed_workspaces = optional(set(object({
        workspace_id = string
      })), [])
    })), [])
    allowed_gateways = optional(set(object({
      id = string
    })), [])
  }))
  description = "Fabric workspaces and their identity, RBAC, managed private endpoints, optional network restrictions, and Git outbound policy. Map keys are stable Terraform keys, not resource IDs."
  nullable    = false

  validation {
    condition = alltrue(flatten([
      for workspace in values(var.workspaces) : [
        for assignment in values(workspace.role_assignments) : contains(["Admin", "Contributor", "Member", "Viewer"], assignment.role)
      ]
    ]))
    error_message = "Workspace roles must be Admin, Contributor, Member, or Viewer."
  }
  validation {
    condition = alltrue(flatten([
      for workspace in values(var.workspaces) : [
        for assignment in values(workspace.role_assignments) : contains(["Group", "ServicePrincipal", "ServicePrincipalProfile", "User"], assignment.principal.type)
      ]
    ]))
    error_message = "Workspace principal types must be Group, ServicePrincipal, ServicePrincipalProfile, or User."
  }
  validation {
    condition     = alltrue([for workspace in values(var.workspaces) : !workspace.private_link_ready_for_lockdown || (workspace.enable_network_restrictions && workspace.private_link != null)])
    error_message = "private_link_ready_for_lockdown can be true only when network restrictions and private_link are configured."
  }
  validation {
    condition     = var.enable_preview_workspace_encryption || alltrue([for workspace in values(var.workspaces) : workspace.customer_managed_key == null])
    error_message = "customer_managed_key can be set only when enable_preview_workspace_encryption is true (and the root Fabric provider has preview = true), because fabric_workspace_encryption is a preview resource."
  }
  validation {
    condition     = alltrue(flatten([for workspace in values(var.workspaces) : [for rule in workspace.outbound_connection_rules : rule.default_action == "Deny"]]))
    error_message = "Every outbound connection rule must use default_action Deny and allow only approved endpoints or workspaces."
  }
  validation {
    condition     = alltrue([for workspace in values(var.workspaces) : contains(["Allow", "Deny"], workspace.git_outbound_default_action)])
    error_message = "git_outbound_default_action must be Allow or Deny."
  }
  validation {
    condition = alltrue([
      for workspace in values(var.workspaces) :
      workspace.enable_network_restrictions || workspace.git_outbound_default_action == "Allow"
    ])
    error_message = "git_outbound_default_action can be Deny only when enable_network_restrictions is true."
  }
  validation {
    condition = alltrue([
      for workspace in values(var.workspaces) :
      workspace.private_link == null || can(provider::azapi::parse_resource_id("Microsoft.Network/privateDnsZones", workspace.private_link.private_dns_zone_resource_id))
    ])
    error_message = "Each private_link.private_dns_zone_resource_id must be a valid private DNS zone resource ID."
  }
  validation {
    condition = alltrue([
      for workspace in values(var.workspaces) :
      workspace.private_link == null || can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", workspace.private_link.resource_group_resource_id))
    ])
    error_message = "Each private_link.resource_group_resource_id must be a valid resource-group resource ID."
  }
  validation {
    condition = alltrue([
      for workspace in values(var.workspaces) :
      workspace.private_link == null || can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", workspace.private_link.subnet_resource_id))
    ])
    error_message = "Each private_link.subnet_resource_id must be a valid virtual-network subnet resource ID."
  }
  validation {
    condition = alltrue([
      for workspace in values(var.workspaces) : workspace.enable_network_restrictions || (
        length(workspace.outbound_connection_rules) == 0 && length(workspace.allowed_gateways) == 0
      )
    ])
    error_message = "outbound_connection_rules and allowed_gateways require enable_network_restrictions to be true."
  }
  validation {
    condition = alltrue([
      for workspace in values(var.workspaces) :
      workspace.private_link == null || length(workspace.private_link.tags) == 0 || workspace.private_link.tags == coalesce(var.tags, {})
    ])
    error_message = "Private-link resources use the standard module tags input (TFFR9). Move distinct legacy private_link.tags overrides to the Fabric zone's tags; an override must be empty or identical to the module tags, never silently discarded."
  }
}

variable "domain_role_assignments" {
  type = map(set(object({
    id   = string
    type = string
  })))
  default     = {}
  description = "Domain role assignments keyed by Admins or Contributors. Principal IDs must be supplied by the caller. Prefer Entra groups."
  nullable    = false

  validation {
    condition     = alltrue([for role in keys(var.domain_role_assignments) : contains(["Admins", "Contributors"], role)])
    error_message = "Domain role keys must be Admins or Contributors."
  }
  validation {
    condition = alltrue(flatten([
      for principals in values(var.domain_role_assignments) : [
        for principal in principals : contains(["Group", "User"], principal.type)
      ]
    ]))
    error_message = "Fabric domain principals must have type Group or User."
  }
}

variable "enable_preview_domain_workspace_assignment" {
  type        = bool
  default     = false
  description = "THIS IS A VARIABLE USED FOR A PREVIEW SERVICE/FEATURE, MICROSOFT MAY NOT PROVIDE SUPPORT FOR THIS, PLEASE CHECK THE PRODUCT DOCS FOR CLARIFICATION. Opt in to the preview Fabric domain workspace assignment resource (`fabric_domain_workspace_assignments`) only; no other resource in this module is affected. The root Fabric provider must also set preview = true."
  nullable    = false
}

variable "enable_preview_workspace_encryption" {
  type        = bool
  default     = false
  description = "THIS IS A VARIABLE USED FOR A PREVIEW SERVICE/FEATURE, MICROSOFT MAY NOT PROVIDE SUPPORT FOR THIS, PLEASE CHECK THE PRODUCT DOCS FOR CLARIFICATION. Opt in to the preview Fabric workspace encryption resource (`fabric_workspace_encryption`) only; no other resource in this module is affected. Required when any workspace sets `customer_managed_key`. The root Fabric provider must also set preview = true."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls whether anonymous module usage telemetry is enabled for this module and its child modules."
  nullable    = false
}

variable "ignore_body_changes" {
  type = object({
    fabric_private_link_services_for_fabric           = optional(list(string), [])
    network_private_endpoints                         = optional(list(string), [])
    network_private_endpoints_private_dns_zone_groups = optional(list(string), [])
  })
  default     = {}
  description = "Body-relative dot-notation paths ignored on resources mutated outside Terraform (TFFR8). On updates, AzAPI sends the live Azure value for each ignored path that Azure returns, and the configured value only where Azure returns none. `fabric_private_link_services_for_fabric`: workspace private-link services; `network_private_endpoints`: private endpoints; `network_private_endpoints_private_dns_zone_groups`: their private DNS zone groups. List items cannot be targeted individually."
  nullable    = false
}

variable "resource_types" {
  type = object({
    fabric_private_link_services_for_fabric           = optional(string, "Microsoft.Fabric/privateLinkServicesForFabric@2024-06-01")
    network_private_endpoints                         = optional(string, "Microsoft.Network/privateEndpoints@2024-05-01")
    network_private_endpoints_private_dns_zone_groups = optional(string, "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01")
  })
  default     = {}
  description = "AzAPI resource types and tested stable API versions (TFFR6). `fabric_private_link_services_for_fabric`: workspace private-link services (2024-06-01); `network_private_endpoints`: private endpoints (2024-05-01); `network_private_endpoints_private_dns_zone_groups`: private DNS zone groups (2024-05-01)."
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string), ["409 Conflict", "429 Too Many Requests"])
    interval_seconds     = optional(number, null)
    max_interval_seconds = optional(number, null)
  })
  default     = null
  description = "Retry configuration applied to AzAPI resources created directly by this module. Defaults to null (no custom retry)."
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "Standard Azure tags applied to the owned workspace private-link services and private endpoints. Configure zone-level tags through the root; legacy private_link.tags must be empty or identical to this value."
}

variable "timeouts" {
  type = object({
    create = optional(string, "30m")
    delete = optional(string, "30m")
    read   = optional(string, "5m")
    update = optional(string, "30m")
  })
  default     = null
  description = "Timeouts applied to AzAPI resources created directly by this module. Defaults to null (provider defaults) when not supplied."
}
