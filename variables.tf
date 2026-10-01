variable "data_management_landing_zones" {
  type = map(object({
    capacity_administration_members = set(string)
    capacity_name                   = string
    capacity_role_assignments = optional(map(object({
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    capacity_sku_name = string
    enable_telemetry  = optional(bool, true)
    location          = string
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
    resource_group_name        = string
    resource_group_resource_id = optional(string)
    tags                       = optional(map(string), {})
  }))
  description = "Azure data management landing zones and Fabric capacities. Capacity administrators must be Entra user UPNs or service-principal object IDs."
  nullable    = false

  validation {
    condition     = length(var.data_management_landing_zones) > 0
    error_message = "At least one Fabric data management landing zone is required because OneLake is the central data layer."
  }
  validation {
    condition = alltrue([
      for zone in values(var.data_management_landing_zones) :
      zone.resource_group_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", zone.resource_group_resource_id))
    ])
    error_message = "Each data management landing zone resource_group_resource_id must be a valid resource-group resource ID or null."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.data_management_landing_zones) : [
        for assignment in values(zone.capacity_role_assignments) :
        assignment.delegated_managed_identity_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", assignment.delegated_managed_identity_resource_id))
      ]
    ]))
    error_message = "Each capacity role assignment delegated_managed_identity_resource_id must be a valid user-assigned managed identity resource ID."
  }
}

variable "fabric_data_landing_zones" {
  type = map(object({
    capacity_key                               = string
    domain_description                         = string
    domain_display_name                        = string
    enable_preview_domain_workspace_assignment = optional(bool, false)
    enable_preview_workspace_encryption        = optional(bool, false)
    tags                                       = optional(map(string), {})
    domain_role_assignments = optional(map(set(object({
      id   = string
      type = string
    }))), {})
    workspaces = map(object({
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
  }))
  description = "THIS IS A VARIABLE USED FOR A PREVIEW SERVICE/FEATURE, MICROSOFT MAY NOT PROVIDE SUPPORT FOR THIS, PLEASE CHECK THE PRODUCT DOCS FOR CLARIFICATION. Fabric business-domain landing zones. Only the nested `enable_preview_domain_workspace_assignment` and `enable_preview_workspace_encryption` attributes opt in to preview Fabric provider resources (`fabric_domain_workspace_assignments` and `fabric_workspace_encryption` respectively); everything else in this variable is stable. capacity_key must reference a key in data_management_landing_zones."
  nullable    = false

  validation {
    condition     = length(var.fabric_data_landing_zones) > 0
    error_message = "At least one Fabric data landing zone is required because OneLake is the central data layer."
  }
  validation {
    condition     = alltrue([for zone in values(var.fabric_data_landing_zones) : contains(keys(var.data_management_landing_zones), zone.capacity_key)])
    error_message = "Every data landing zone capacity_key must exist in data_management_landing_zones."
  }
  validation {
    condition = alltrue([
      for zone in values(var.fabric_data_landing_zones) :
      zone.enable_preview_workspace_encryption || alltrue([for workspace in values(zone.workspaces) : workspace.customer_managed_key == null])
    ])
    error_message = "customer_managed_key can be set only when enable_preview_workspace_encryption is true (and the root Fabric provider has preview = true), because fabric_workspace_encryption is a preview resource."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.fabric_data_landing_zones) : [
        for workspace in values(zone.workspaces) :
        workspace.private_link == null || can(provider::azapi::parse_resource_id("Microsoft.Network/privateDnsZones", workspace.private_link.private_dns_zone_resource_id))
      ]
    ]))
    error_message = "Each Fabric private_link.private_dns_zone_resource_id must be a valid private DNS zone resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.fabric_data_landing_zones) : [
        for workspace in values(zone.workspaces) :
        workspace.private_link == null || can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", workspace.private_link.resource_group_resource_id))
      ]
    ]))
    error_message = "Each Fabric private_link.resource_group_resource_id must be a valid resource-group resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.fabric_data_landing_zones) : [
        for workspace in values(zone.workspaces) :
        workspace.private_link == null || can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", workspace.private_link.subnet_resource_id))
      ]
    ]))
    error_message = "Each Fabric private_link.subnet_resource_id must be a valid virtual-network subnet resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region used for pattern telemetry (SFR4). Each landing zone retains its independently supplied resource location."
  nullable    = false
}

variable "tenant_id" {
  type        = string
  description = "Microsoft Entra tenant ID. Supply it from the deployment environment; never commit a tenant ID to source control."
  nullable    = false
}

variable "capacity_activation_wait_duration" {
  type        = string
  default     = "30s"
  description = "Duration to wait after each Fabric capacity is created before looking it up through the Fabric API, mitigating (not eliminating) the control-plane propagation delay between ARM capacity creation and Fabric API discoverability. A string parsed as a Go duration, for example \"30s\" or \"2m\". Increase this if the postcondition on data.fabric_capacity still reports the capacity as not Active."
  nullable    = false
}

variable "databricks_data_landing_zones" {
  type = map(object({
    access_connector_name = string
    access_connector_lock = optional(object({
      kind = string
      name = optional(string, null)
    }))
    access_connector_role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    customer_managed_key = optional(object({
      dbfs_root_key_role_assignment = optional(object({
        key_vault_resource_id = string
      }))
      dbfs_root_key_vault_key_id                      = optional(string)
      managed_disk_key_vault_key_id                   = optional(string)
      managed_disk_key_vault_resource_id              = optional(string)
      managed_disk_rotation_to_latest_version_enabled = optional(bool, false)
      managed_services_key_vault_key_id               = optional(string)
      managed_services_key_vault_resource_id          = optional(string)
    }))
    default_storage_firewall_enabled  = optional(bool, true)
    enable_telemetry                  = optional(bool, true)
    infrastructure_encryption_enabled = optional(bool, true)
    location                          = string
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
    managed_resource_group_name                          = string
    network_security_group_rules_required                = optional(string, "AllRules")
    no_public_ip                                         = optional(bool, true)
    private_subnet_name                                  = string
    private_subnet_network_security_group_association_id = string
    public_network_access_enabled                        = optional(bool, true)
    public_subnet_name                                   = string
    public_subnet_network_security_group_association_id  = string
    resource_group_name                                  = string
    resource_group_resource_id                           = optional(string)
    sku                                                  = string
    virtual_network_id                                   = string
    workspace_name                                       = string
    tags                                                 = optional(map(string), {})
    onelake_targets = optional(map(object({
      endpoint_host       = string
      fabric_item_id      = string
      fabric_item_type    = string
      fabric_workspace_id = string
      path                = optional(string, "")
    })), {})
    diagnostic_settings = optional(map(object({
      name = optional(string, null)
      logs = optional(set(object({
        category       = optional(string, null)
        category_group = optional(string, null)
        enabled        = optional(bool, true)
        retention_policy = optional(object({
          days    = optional(number, 0)
          enabled = optional(bool, false)
        }), {})
      })), [])
      metrics = optional(set(object({
        category = optional(string, null)
        enabled  = optional(bool, true)
        retention_policy = optional(object({
          days    = optional(number, 0)
          enabled = optional(bool, false)
        }), {})
      })), [])
      log_analytics_destination_type           = optional(string, "Dedicated")
      workspace_resource_id                    = optional(string, null)
      storage_account_resource_id              = optional(string, null)
      event_hub_authorization_rule_resource_id = optional(string, null)
      event_hub_name                           = optional(string, null)
      marketplace_partner_resource_id          = optional(string, null)
    })), {})
  }))
  default     = {}
  description = "Azure Databricks data landing zones that use existing OneLake items as the shared analytical data layer. customer_managed_key.dbfs_root_key_role_assignment.key_vault_resource_id names the Azure RBAC vault that hosts dbfs_root_key_vault_key_id; the zone then grants the workspace storage identity Key Vault Crypto Service Encryption User on that key between workspace preparation and key binding, so one apply creates an encrypted workspace (the deploying identity needs Microsoft.Authorization/roleAssignments/write on the key). Legacy managed_disk_key_vault_resource_id and managed_services_key_vault_resource_id hints are retained only to reject them explicitly; encryption keys are selected by key URLs, not these ARM IDs."
  nullable    = false

  validation {
    condition = alltrue(flatten([
      for zone in values(var.databricks_data_landing_zones) : [
        for assignment in values(zone.access_connector_role_assignments) :
        assignment.delegated_managed_identity_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", assignment.delegated_managed_identity_resource_id))
      ]
    ]))
    error_message = "Each access connector role assignment delegated_managed_identity_resource_id must be a valid user-assigned managed identity resource ID."
  }
  validation {
    condition = alltrue([
      for zone in values(var.databricks_data_landing_zones) :
      zone.customer_managed_key == null ? true : (
        zone.customer_managed_key.managed_disk_key_vault_resource_id == null &&
        zone.customer_managed_key.managed_services_key_vault_resource_id == null
      )
    ])
    error_message = "managed_disk_key_vault_resource_id and managed_services_key_vault_resource_id are unsupported legacy hints. Supply only key URLs; these vault ARM IDs neither select encryption keys nor grant access."
  }
  validation {
    condition = alltrue([
      for zone in values(var.databricks_data_landing_zones) :
      try(zone.customer_managed_key.dbfs_root_key_role_assignment, null) == null ? true :
      can(provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults", zone.customer_managed_key.dbfs_root_key_role_assignment.key_vault_resource_id))
    ])
    error_message = "Each Databricks customer_managed_key.dbfs_root_key_role_assignment.key_vault_resource_id must be a valid Azure Key Vault resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.databricks_data_landing_zones) : zone.customer_managed_key == null ? [] : [
        for resource_id in compact([
          zone.customer_managed_key.managed_disk_key_vault_resource_id,
          zone.customer_managed_key.managed_services_key_vault_resource_id
        ]) : can(provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults", resource_id))
      ]
    ]))
    error_message = "Each Databricks customer-managed key vault resource ID must be a valid Azure Key Vault resource ID."
  }
  validation {
    condition = alltrue([
      for zone in values(var.databricks_data_landing_zones) :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", zone.private_subnet_network_security_group_association_id)) &&
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", zone.public_subnet_network_security_group_association_id))
    ])
    error_message = "Each Databricks subnet NSG association ID must identify a valid virtual-network subnet."
  }
  validation {
    condition = alltrue([
      for zone in values(var.databricks_data_landing_zones) :
      zone.resource_group_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", zone.resource_group_resource_id))
    ])
    error_message = "Each Databricks resource_group_resource_id must be a valid resource-group resource ID or null."
  }
  validation {
    condition = alltrue([
      for zone in values(var.databricks_data_landing_zones) :
      can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks", zone.virtual_network_id))
    ])
    error_message = "Each Databricks virtual_network_id must be a valid virtual-network resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.databricks_data_landing_zones) : [
        for setting in values(zone.diagnostic_settings) :
        setting.event_hub_authorization_rule_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.EventHub/namespaces/authorizationRules", setting.event_hub_authorization_rule_resource_id))
      ]
    ]))
    error_message = "Each Databricks diagnostic eventhub_authorization_rule_id must be a valid Event Hubs namespace authorization-rule resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.databricks_data_landing_zones) : [
        for setting in values(zone.diagnostic_settings) :
        setting.workspace_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.OperationalInsights/workspaces", setting.workspace_resource_id))
      ]
    ]))
    error_message = "Each Databricks diagnostic log_analytics_workspace_id must be a valid Log Analytics workspace resource ID."
  }
  validation {
    condition = alltrue(flatten([
      for zone in values(var.databricks_data_landing_zones) : [
        for setting in values(zone.diagnostic_settings) :
        setting.storage_account_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.Storage/storageAccounts", setting.storage_account_resource_id))
      ]
    ]))
    error_message = "Each Databricks diagnostic storage_account_id must be a valid storage-account resource ID."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "Common Azure tags merged into every data management, Fabric, and Databricks landing zone."
}
