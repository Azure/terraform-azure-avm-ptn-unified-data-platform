locals {
  resource_group_resource_id = var.resource_group_resource_id == null ? module.resource_group[0].resource_id : var.resource_group_resource_id
  # try() (not the `!= null &&` pattern) keeps this null guard independent of whether
  # Terraform short-circuits `&&`/`||`, which it only does from 1.12 onwards. The module
  # already requires 1.12, but the guard stays version-independent by design.
  workspace_customer_managed_key_enabled = try(var.databricks_customer_managed_keys.dbfs_root_key_vault_key_id, null) != null
  diagnostic_setting_names = {
    for key, setting in var.diagnostic_settings :
    key => setting.name != null ? setting.name : "diag-${substr(var.workspace_name, 0, 64)}-${sha256(key)}"
  }
  # Azure returns every individual category, including disabled ones.
  diagnostic_setting_logs = {
    for key, setting in module.diagnostic_settings_interface.diagnostic_settings_azapi_v2 :
    key => anytrue([for log in var.diagnostic_settings[key].logs : log.category_group != null]) ? setting.body.properties.logs : concat(
      coalesce(setting.body.properties.logs, []),
      [
        for category in sort(data.azapi_resource_list.diagnostic_categories[0].output.log_categories) : {
          category      = category
          categoryGroup = null
          enabled       = false
          retentionPolicy = {
            days    = 0
            enabled = false
          }
        } if !contains([for log in var.diagnostic_settings[key].logs : log.category], category)
      ]
    )
  }
  managed_resource_group_id  = "/subscriptions/${provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", local.resource_group_resource_id).subscription_id}/resourceGroups/${var.managed_resource_group_name}"
  managed_disk_key_parts     = try(regex("(?i)^(https://[^/]+/)keys/([^/]+)/([^/]+)$", var.databricks_customer_managed_keys.managed_disk_key_vault_key_id), null)
  managed_services_key_parts = try(regex("(?i)^(https://[^/]+/)keys/([^/]+)/([^/]+)$", var.databricks_customer_managed_keys.managed_services_key_vault_key_id), null)
  dbfs_root_key_parts        = try(regex("(?i)^(https://[^/]+)/keys/([^/]+)(?:/([^/]+))?$", var.databricks_customer_managed_keys.dbfs_root_key_vault_key_id), null)
  # Opt-in grant for the workspace storage identity, scoped to the root DBFS key itself so
  # every key version is covered. Only the object's presence decides the count, which keeps
  # plans valid when the vault or key is created in the same configuration.
  dbfs_root_key_role_assignment = try(var.databricks_customer_managed_keys.dbfs_root_key_role_assignment, null)
  dbfs_root_key_role_assignment_scope = try(
    "${local.dbfs_root_key_role_assignment.key_vault_resource_id}/keys/${local.dbfs_root_key_parts[1]}",
    null
  )
  # Key Vault Crypto Service Encryption User, the role Microsoft documents for this identity.
  dbfs_root_key_role_definition_id = try(
    "/subscriptions/${provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults", local.dbfs_root_key_role_assignment.key_vault_resource_id).subscription_id}/providers/Microsoft.Authorization/roleDefinitions/e147488a-f6f5-4113-8e2d-b22465e65bf6",
    null
  )
  # A new Azure RBAC grant reaches Key Vault after a delay, during which the binding fails
  # with KeyVaultAuthenticationFailure, or with ApplicationUpdateFail when Databricks cannot
  # update its managed storage account. Used only when the module grants access itself and
  # the caller has not supplied retry (TFFR7 module default; a caller value replaces it).
  dbfs_root_key_retry = var.retry != null || local.dbfs_root_key_role_assignment == null ? var.retry : {
    error_message_regex  = ["(?i)KeyVaultAuthenticationFailure", "(?i)authentication issue on the key ?vault", "(?i)ApplicationUpdateFail"]
    interval_seconds     = 15
    max_interval_seconds = 60
  }
  dbfs_root_encryption = {
    keySource   = local.dbfs_root_key_parts == null ? "Default" : "Microsoft.Keyvault"
    KeyName     = local.dbfs_root_key_parts == null ? null : local.dbfs_root_key_parts[1]
    keyvaulturi = local.dbfs_root_key_parts == null ? null : local.dbfs_root_key_parts[0]
    keyversion  = local.dbfs_root_key_parts == null ? null : (local.dbfs_root_key_parts[2] == null ? "" : local.dbfs_root_key_parts[2])
  }
  workspace_encryption_entities = merge(
    local.managed_disk_key_parts == null ? {} : {
      managedDisk = {
        keySource = "Microsoft.Keyvault"
        keyVaultProperties = {
          keyVaultUri = local.managed_disk_key_parts[0]
          keyName     = local.managed_disk_key_parts[1]
          keyVersion  = local.managed_disk_key_parts[2]
        }
        rotationToLatestKeyVersionEnabled = var.databricks_customer_managed_keys.managed_disk_rotation_to_latest_version_enabled
      }
    },
    local.managed_services_key_parts == null ? {} : {
      managedServices = {
        keySource = "Microsoft.Keyvault"
        keyVaultProperties = {
          keyVaultUri = local.managed_services_key_parts[0]
          keyName     = local.managed_services_key_parts[1]
          keyVersion  = local.managed_services_key_parts[2]
        }
      }
    }
  )
  workspace_properties = merge({
    accessConnector = {
      id           = module.access_connector.resource_id
      identityType = "SystemAssigned"
    }
    computeMode            = "Hybrid"
    defaultStorageFirewall = var.default_storage_firewall_enabled ? "Enabled" : "Disabled"
    managedResourceGroupId = local.managed_resource_group_id
    publicNetworkAccess    = var.public_network_access_enabled ? "Enabled" : "Disabled"
    requiredNsgRules       = var.network_security_group_rules_required
    parameters = merge({
      customVirtualNetworkId  = { value = var.virtual_network_id }
      customPublicSubnetName  = { value = var.public_subnet_name }
      customPrivateSubnetName = { value = var.private_subnet_name }
      enableNoPublicIp        = { value = var.no_public_ip }
      },
      var.infrastructure_encryption_enabled ? { requireInfrastructureEncryption = { value = true } } : {},
      # The root DBFS key itself is bound later by azapi_update_resource.dbfs_root_key, once
      # the storage identity exists and can use the key. The service rejects
      # parameters.encryption in the create request (InvalidEncryptionConfiguration).
      local.workspace_customer_managed_key_enabled ? { prepareEncryption = { value = true } } : {}
    )
    }, length(local.workspace_encryption_entities) == 0 ? {} : {
    encryption = { entities = local.workspace_encryption_entities }
  })
}
