variable "access_connector_name" {
  type        = string
  description = "Name of the Azure Databricks Access Connector whose managed identity authenticates to OneLake."
  nullable    = false
}

variable "location" {
  type        = string
  description = "Approved Azure region for the Azure Databricks workspace, access connector, and optional resource group."
  nullable    = false
}

variable "managed_resource_group_name" {
  type        = string
  description = "Name of the Azure-managed resource group for the Azure Databricks workspace."
  nullable    = false
}

variable "private_subnet_name" {
  type        = string
  description = "Name of the delegated private/container subnet in the caller-managed virtual network."
  nullable    = false
}

variable "private_subnet_network_security_group_association_id" {
  type        = string
  description = "Resource ID of the private subnet NSG association."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", var.private_subnet_network_security_group_association_id))
    error_message = "private_subnet_network_security_group_association_id must identify a valid virtual-network subnet."
  }
}

variable "public_subnet_name" {
  type        = string
  description = "Name of the delegated public/host subnet in the caller-managed virtual network. The workspace still deploys cluster nodes without public IPs."
  nullable    = false
}

variable "public_subnet_network_security_group_association_id" {
  type        = string
  description = "Resource ID of the public subnet NSG association."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", var.public_subnet_network_security_group_association_id))
    error_message = "public_subnet_network_security_group_association_id must identify a valid virtual-network subnet."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create when resource_group_resource_id is null."
  nullable    = false
}

variable "sku" {
  type        = string
  description = "Azure Databricks workspace SKU. OneLake catalog federation requires Premium."
  nullable    = false

  validation {
    condition     = lower(var.sku) == "premium"
    error_message = "sku must be premium because OneLake catalog federation requires a Premium Azure Databricks workspace."
  }
}

variable "virtual_network_id" {
  type        = string
  description = "Resource ID of the caller-managed virtual network used for Azure Databricks VNet injection."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks", var.virtual_network_id))
    error_message = "virtual_network_id must be a valid virtual-network resource ID."
  }
}

variable "workspace_name" {
  type        = string
  description = "Name of the Azure Databricks workspace."
  nullable    = false
}

variable "access_connector_lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = "Management lock applied to the Databricks Access Connector."

  validation {
    # try() keeps this null guard independent of whether Terraform short-circuits `||`,
    # which it only does from 1.12 onwards. The module already requires 1.12, but the
    # guard stays version-independent by design.
    condition     = var.access_connector_lock == null || try(contains(["CanNotDelete", "ReadOnly"], var.access_connector_lock.kind), false)
    error_message = "access_connector_lock.kind must be CanNotDelete or ReadOnly."
  }
}

variable "access_connector_role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = "ARM role assignments to create on the Databricks Access Connector."
  nullable    = false

  validation {
    condition = alltrue([
      for assignment in values(var.access_connector_role_assignments) :
      assignment.delegated_managed_identity_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", assignment.delegated_managed_identity_resource_id))
    ])
    error_message = "Each access connector role assignment delegated_managed_identity_resource_id must be a valid user-assigned managed identity resource ID."
  }
}

variable "databricks_customer_managed_keys" {
  type = object({
    dbfs_root_key_role_assignment = optional(object({
      key_vault_resource_id = string
    }))
    dbfs_root_key_vault_key_id    = optional(string)
    managed_disk_key_vault_key_id = optional(string)
    # Rejection sentinels: removing these attributes would silently drop legacy values
    # during Terraform's object conversion before validation could see them.
    managed_disk_key_vault_resource_id              = optional(string)
    managed_disk_rotation_to_latest_version_enabled = optional(bool, false)
    managed_services_key_vault_key_id               = optional(string)
    managed_services_key_vault_resource_id          = optional(string)
  })
  default     = null
  description = "Customer-managed keys for Databricks root DBFS, managed disks, and managed services. Root DBFS: Databricks creates the workspace storage account identity (workspace_storage_account_identity) when the workspace is prepared for encryption, and that identity needs Key Vault Crypto Service Encryption User on the key before the key is bound. Set dbfs_root_key_role_assignment.key_vault_resource_id to the Azure RBAC vault that hosts dbfs_root_key_vault_key_id to let the module grant that role on the key between preparation and binding, so one apply creates an encrypted workspace; the deploying identity then needs Microsoft.Authorization/roleAssignments/write on the key. Without it, the first apply prepares the workspace but cannot bind the key until you grant that role yourself; apply again after granting. docs/security.md covers existing grants, key or vault changes, and removing the grant. Managed disks: grant workspace_managed_disk_identity access to its key after creation. Managed services: grant the AzureDatabricks first-party application access to its key before creation. managed_disk_key_vault_resource_id and managed_services_key_vault_resource_id are rejected legacy inputs; ARM uses the versioned key URLs. This is not named customer_managed_key because the AVM single-key interface cannot represent all three independent surfaces. Removing a root DBFS key sends Default to revert to platform encryption."

  validation {
    condition = var.databricks_customer_managed_keys == null ? true : (
      var.databricks_customer_managed_keys.dbfs_root_key_role_assignment == null ? true : (
        var.databricks_customer_managed_keys.dbfs_root_key_vault_key_id == null ? false :
        can(provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults", var.databricks_customer_managed_keys.dbfs_root_key_role_assignment.key_vault_resource_id))
      )
    )
    error_message = "dbfs_root_key_role_assignment requires dbfs_root_key_vault_key_id and a valid Azure Key Vault resource ID in key_vault_resource_id."
  }
  validation {
    condition = var.databricks_customer_managed_keys == null ? true : (
      var.databricks_customer_managed_keys.dbfs_root_key_role_assignment == null ? true : try(
        lower(provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults", var.databricks_customer_managed_keys.dbfs_root_key_role_assignment.key_vault_resource_id).name) ==
        lower(regex("(?i)^https://([^.]+)\\.", var.databricks_customer_managed_keys.dbfs_root_key_vault_key_id)[0]),
        true
      )
    )
    error_message = "dbfs_root_key_role_assignment.key_vault_resource_id must identify the vault that hosts dbfs_root_key_vault_key_id."
  }
  validation {
    condition = var.databricks_customer_managed_keys == null || anytrue([
      var.databricks_customer_managed_keys.dbfs_root_key_vault_key_id != null,
      var.databricks_customer_managed_keys.managed_disk_key_vault_key_id != null,
      var.databricks_customer_managed_keys.managed_services_key_vault_key_id != null
    ])
    error_message = "databricks_customer_managed_keys must configure at least one key ID."
  }
  validation {
    condition = var.databricks_customer_managed_keys == null || alltrue([
      for key_id in compact([
        var.databricks_customer_managed_keys.dbfs_root_key_vault_key_id
      ]) : can(regex("(?i)^https://[a-z0-9-]+\\.vault\\.azure\\.net/keys/[^/]+(/[^/]+)?$", key_id))
    ])
    error_message = "dbfs_root_key_vault_key_id must be a valid Azure Key Vault key URL, versioned or versionless."
  }
  # The workspace encryption API requires an explicit version for these two surfaces.
  validation {
    condition = var.databricks_customer_managed_keys == null || alltrue([
      for key_id in compact([
        var.databricks_customer_managed_keys.managed_disk_key_vault_key_id,
        var.databricks_customer_managed_keys.managed_services_key_vault_key_id
      ]) : can(regex("(?i)^https://[a-z0-9-]+\\.vault\\.azure\\.net/keys/[^/]+/[^/]+$", key_id))
    ])
    error_message = "managed_disk_key_vault_key_id and managed_services_key_vault_key_id must be versioned Azure Key Vault key URLs (https://<vault>.vault.azure.net/keys/<name>/<version>); the Databricks workspace encryption API requires an explicit key version for these surfaces. Use managed_disk_rotation_to_latest_version_enabled to follow new managed-disk key versions automatically."
  }
  validation {
    condition = var.databricks_customer_managed_keys == null || (
      var.databricks_customer_managed_keys.managed_disk_key_vault_resource_id == null &&
      var.databricks_customer_managed_keys.managed_services_key_vault_resource_id == null
    )
    error_message = "managed_disk_key_vault_resource_id and managed_services_key_vault_resource_id are unsupported legacy inputs. Omit them; Databricks ARM binds these keys by their versioned Key Vault URLs, not vault resource IDs."
  }
}

variable "default_storage_firewall_enabled" {
  type        = bool
  default     = true
  description = "Whether to block public access to the Azure Databricks workspace default storage."
  nullable    = false
}

variable "diagnostic_settings" {
  type = map(object({
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
  }))
  default     = {}
  description = "Diagnostic settings keyed by stable Terraform keys using the AVM diagnostic_settings_v2 shape. Unnamed entries use diag-<workspace-name-prefix>-<SHA256(map-key)>, at most 134 characters. Explicit and generated names must be distinct (case-insensitive). Logs, metrics and enabled flags are preserved. Dedicated is sent unchanged; AzureDiagnostics is translated to null as required by ARM. Leave retention_policy disabled; configure retention on Log Analytics tables or with a Storage lifecycle management policy."
  nullable    = false

  validation {
    condition     = alltrue([for _, v in var.diagnostic_settings : contains(["Dedicated", "AzureDiagnostics"], v.log_analytics_destination_type)])
    error_message = "Log analytics destination type must be one of: 'Dedicated', 'AzureDiagnostics'."
  }
  validation {
    condition = alltrue([
      for setting in values(var.diagnostic_settings) :
      setting.name == null || (length(trimspace(setting.name)) > 0 && length(setting.name) <= 260)
    ])
    error_message = "Explicit diagnostic setting names must be non-empty, non-whitespace strings of at most 260 characters; omit name to generate one from the map key."
  }
  validation {
    condition = length(distinct([
      for key, setting in var.diagnostic_settings :
      lower(setting.name != null ? setting.name : "diag-${substr(var.workspace_name, 0, 64)}-${sha256(key)}")
    ])) == length(var.diagnostic_settings)
    error_message = "Diagnostic setting names must be unique, including collisions between explicit names and names generated from map keys."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings : (
        v.event_hub_authorization_rule_resource_id != null ||
        v.workspace_resource_id != null ||
        v.storage_account_resource_id != null ||
        v.marketplace_partner_resource_id != null
      ) && (length(v.logs) > 0 || length(v.metrics) > 0)
    ])
    error_message = "Each diagnostic setting requires a destination and at least one log or metric category."
  }
  # Diagnostic-settings storage retention was retired by Azure Monitor on 30 September
  # 2025 (https://learn.microsoft.com/azure/azure-monitor/data-collection/migrate-to-azure-storage-lifecycle-policy).
  # The attribute stays in the interface only because it is part of the AVM
  # diagnostic_settings_v2 shape; any request to enable it is rejected here rather than
  # silently ignored or sent to an API that no longer honours it.
  validation {
    condition = alltrue(flatten([
      for _, v in var.diagnostic_settings : [
        [for log in v.logs : !log.retention_policy.enabled && log.retention_policy.days == 0],
        [for metric in v.metrics : !metric.retention_policy.enabled && metric.retention_policy.days == 0],
      ]
    ]))
    error_message = "retention_policy is not supported: Azure Monitor retired diagnostic-settings storage retention on 30 September 2025. Leave retention_policy unset and configure retention on the Log Analytics tables or with an Azure Storage lifecycle management policy."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings :
      v.event_hub_authorization_rule_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.EventHub/namespaces/authorizationRules", v.event_hub_authorization_rule_resource_id))
    ])
    error_message = "Each diagnostic setting event_hub_authorization_rule_resource_id must be a valid Event Hubs namespace authorization-rule resource ID."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings :
      v.workspace_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.OperationalInsights/workspaces", v.workspace_resource_id))
    ])
    error_message = "Each diagnostic setting workspace_resource_id must be a valid Log Analytics workspace resource ID."
  }
  validation {
    condition = alltrue([
      for _, v in var.diagnostic_settings :
      v.storage_account_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.Storage/storageAccounts", v.storage_account_resource_id))
    ])
    error_message = "Each diagnostic setting storage_account_resource_id must be a valid storage-account resource ID."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls whether anonymous module usage telemetry is enabled. No customer data or deployment values are collected."
  nullable    = false
}

variable "ignore_body_changes" {
  type = object({
    authorization_locks            = optional(list(string), [])
    authorization_role_assignments = optional(list(string), [])
    databricks_workspaces          = optional(list(string), [])
    insights_diagnostic_settings   = optional(list(string), [])
    databricks_access_connectors = optional(object({
      databricks_access_connectors   = optional(list(string), [])
      authorization_locks            = optional(list(string), [])
      authorization_role_assignments = optional(list(string))
    }), {})
  })
  default     = {}
  description = "AzAPI body-relative paths in dot notation: authorization_locks for workspace locks, authorization_role_assignments for the optional root DBFS key grant (whose body the module already ignores after creation), databricks_workspaces for the workspace, insights_diagnostic_settings for diagnostics. On updates, AzAPI sends the live Azure value for each ignored path that Azure returns, and the configured value only where Azure returns none. databricks_access_connectors passes databricks_access_connectors, authorization_locks and authorization_role_assignments paths unchanged to the Access Connector module. AzAPI 2.12/2.13 do not support ignore_body_changes on the separate root DBFS azapi_update_resource binding. The pinned resource-group module does not expose this interface."
  nullable    = false
}

variable "infrastructure_encryption_enabled" {
  type        = bool
  default     = true
  description = "Whether the Azure Databricks workspace default storage uses infrastructure encryption."
  nullable    = false
}

variable "lock" {
  type = object({
    kind  = string
    name  = optional(string, null)
    notes = optional(string, null)
  })
  default     = null
  description = "Management lock applied to the Databricks workspace. kind must be CanNotDelete or ReadOnly."

  validation {
    # try() keeps this null guard independent of whether Terraform short-circuits `||`,
    # which it only does from 1.12 onwards. The module already requires 1.12, but the
    # guard stays version-independent by design.
    condition     = var.lock == null || try(contains(["CanNotDelete", "ReadOnly"], var.lock.kind), false)
    error_message = "lock.kind must be CanNotDelete or ReadOnly."
  }
}

variable "network_security_group_rules_required" {
  type        = string
  default     = "AllRules"
  description = "Azure Databricks required NSG rule mode. Select it to match the approved public or Private Link topology."
  nullable    = false

  validation {
    condition     = contains(["AllRules", "NoAzureDatabricksRules", "NoAzureServiceRules"], var.network_security_group_rules_required)
    error_message = "network_security_group_rules_required must be AllRules, NoAzureDatabricksRules, or NoAzureServiceRules."
  }
}

variable "no_public_ip" {
  type        = bool
  default     = true
  description = "Whether Databricks cluster nodes are prohibited from receiving public IP addresses. Keep the secure default unless an approved exception requires public node IPs."
  nullable    = false
}

variable "onelake_targets" {
  type = map(object({
    endpoint_host       = string
    fabric_item_id      = string
    fabric_item_type    = string
    fabric_workspace_id = string
    path                = optional(string, "")
  }))
  default     = {}
  description = "Existing OneLake items exposed to Databricks. Supply a global, regional, or workspace-private DFS host according to residency and network requirements."
  nullable    = false

  validation {
    condition = alltrue([
      for target in values(var.onelake_targets) :
      can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", target.fabric_workspace_id)) &&
      can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", target.fabric_item_id)) &&
      contains(["Lakehouse", "Warehouse"], target.fabric_item_type) &&
      can(regex("^[A-Za-z0-9.-]+\\.dfs\\.fabric\\.microsoft\\.com$", target.endpoint_host)) &&
      !startswith(target.endpoint_host, "http://") &&
      !startswith(target.endpoint_host, "https://") &&
      !startswith(target.path, "/")
    ])
    error_message = "OneLake targets require RFC 4122 workspace/item GUIDs, a Lakehouse or Warehouse item type, a Fabric DFS host without a URL scheme, and a relative path."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether users can reach the Azure Databricks workspace over its public endpoint. Disable only after the complete Private Link path is deployed and verified."
  nullable    = false
}

variable "resource_group_resource_id" {
  type        = string
  default     = null
  description = "Resource ID of an existing resource group. When null, this module creates resource_group_name."

  validation {
    condition     = var.resource_group_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.resource_group_resource_id))
    error_message = "resource_group_resource_id must be a valid resource-group resource ID or null."
  }
}

variable "resource_types" {
  type = object({
    authorization_locks            = optional(string, "Microsoft.Authorization/locks@2020-05-01")
    authorization_role_assignments = optional(string, "Microsoft.Authorization/roleAssignments@2022-04-01")
    databricks_workspaces          = optional(string, "Microsoft.Databricks/workspaces@2026-01-01")
    insights_diagnostic_settings   = optional(string, "Microsoft.Insights/diagnosticSettings@2021-05-01-preview")
    databricks_access_connectors = optional(object({
      databricks_access_connectors   = optional(string)
      authorization_locks            = optional(string)
      authorization_role_assignments = optional(string)
    }), {})
  })
  default     = {}
  description = "AzAPI types and versions: authorization_locks for workspace locks; authorization_role_assignments for the optional root DBFS key grant; databricks_workspaces for the workspace and root DBFS key binding; insights_diagnostic_settings for diagnostics (preview provides category groups, destination type and marketplace partners absent from the stable version). databricks_access_connectors passes the child module's databricks_access_connectors, authorization_locks and authorization_role_assignments overrides unchanged. The pinned resource-group module does not expose resource_types."
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string), ["409 Conflict", "429 Too Many Requests"])
    interval_seconds     = optional(number, null)
    max_interval_seconds = optional(number, null)
  })
  default     = null
  description = "Retry configuration applied to owned AzAPI resources and cascaded unchanged to the resource-group and Access Connector modules. Defaults to null (no custom retry on owned resources), with one module default: when the module grants root DBFS key access (dbfs_root_key_role_assignment), the root DBFS binding retries KeyVaultAuthenticationFailure and Databricks ApplicationUpdateFail responses every 15 to 60 seconds, within its timeout, while the new Azure RBAC assignment propagates. A misconfigured key therefore fails only when that timeout expires; set timeouts to shorten it. A non-null retry replaces that default, so include those patterns if you set one. AzAPI retries only failed HTTP responses, not failures reported while polling a long-running operation; if the binding fails that way, apply again."
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "Azure tags applied to the resource group, workspace, and access connector."
}

variable "timeouts" {
  type = object({
    create = optional(string, "30m")
    delete = optional(string, "30m")
    read   = optional(string, "5m")
    update = optional(string, "30m")
  })
  default     = null
  description = "Timeouts applied to owned AzAPI resources and cascaded unchanged to the resource-group and Access Connector modules. Defaults to null (provider defaults) when not supplied."
}
