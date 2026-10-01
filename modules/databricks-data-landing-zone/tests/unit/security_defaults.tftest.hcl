mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
    }
  }
}
mock_provider "modtm" {}
mock_provider "random" {}

override_resource {
  target = azapi_resource.this
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-databricks-test/providers/Microsoft.Databricks/workspaces/dbw-test"
    output = {
      properties = {
        workspaceId         = "12345"
        workspaceUrl        = "adb-12345.azuredatabricks.net"
        diskEncryptionSetId = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-managed/providers/Microsoft.Compute/diskEncryptionSets/dbw-disks"
        managedDiskIdentity = {
          principalId = "00000000-0000-0000-0000-000000000003"
          tenantId    = "00000000-0000-0000-0000-000000000002"
          type        = "SystemAssigned"
        }
        storageAccountIdentity = {
          principalId = "00000000-0000-0000-0000-000000000004"
          tenantId    = "00000000-0000-0000-0000-000000000002"
          type        = "SystemAssigned"
        }
      }
    }
  }
}
override_resource {
  target = module.resource_group[0].azapi_resource.this
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-databricks-test"
  }
}
override_resource {
  target = module.access_connector.azapi_resource.this
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-databricks-test/providers/Microsoft.Databricks/accessConnectors/ac-onelake-test"
    output = {
      identity = {
        type        = "SystemAssigned"
        principalId = "00000000-0000-0000-0000-000000000005"
        tenantId    = "00000000-0000-0000-0000-000000000002"
      }
    }
  }
}

variables {
  access_connector_name                                = "ac-onelake-test"
  enable_telemetry                                     = false
  location                                             = "test-region"
  managed_resource_group_name                          = "rg-databricks-managed-test"
  private_subnet_name                                  = "snet-databricks-private"
  private_subnet_network_security_group_association_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-data/subnets/snet-databricks-private"
  public_subnet_name                                   = "snet-databricks-public"
  public_subnet_network_security_group_association_id  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-data/subnets/snet-databricks-public"
  resource_group_name                                  = "rg-databricks-test"
  sku                                                  = "premium"
  virtual_network_id                                   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-data"
  workspace_name                                       = "dbw-test"
}

run "secure_workspace_foundation" {
  command = apply
  variables {
    onelake_targets = {
      curated = {
        endpoint_host       = "test-region-onelake.dfs.fabric.microsoft.com"
        fabric_item_id      = uuidv5("dns", "item.example")
        fabric_item_type    = "Lakehouse"
        fabric_workspace_id = uuidv5("dns", "workspace.example")
        path                = "Tables"
      }
    }
  }
  assert {
    condition = (
      azapi_resource.this.body.sku.name == "premium" &&
      azapi_resource.this.body.properties.computeMode == "Hybrid" &&
      azapi_resource.this.body.properties.parameters.enableNoPublicIp.value &&
      azapi_resource.this.body.properties.parameters.requireInfrastructureEncryption.value &&
      azapi_resource.this.body.properties.defaultStorageFirewall == "Enabled" &&
      azapi_resource.this.body.properties.publicNetworkAccess == "Enabled" &&
      azapi_resource.this.body.properties.requiredNsgRules == "AllRules"
    )
    error_message = "Premium Hybrid workspaces must preserve secure defaults in the actual ARM body."
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.parameters.customVirtualNetworkId.value == var.virtual_network_id &&
      azapi_resource.this.body.properties.parameters.customPublicSubnetName.value == var.public_subnet_name &&
      azapi_resource.this.body.properties.parameters.customPrivateSubnetName.value == var.private_subnet_name &&
      azapi_resource.this.body.properties.managedResourceGroupId == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-databricks-managed-test" &&
      azapi_resource.this.body.properties.accessConnector.id == output.access_connector_id &&
      azapi_resource.this.body.properties.accessConnector.identityType == "SystemAssigned"
    )
    error_message = "VNet injection, managed RG and Access Connector must reach the workspace body."
  }
  assert {
    condition = (
      output.workspace_numeric_id == "12345" &&
      output.workspace_url == "adb-12345.azuredatabricks.net" &&
      output.workspace_managed_disk_identity.principal_id == "00000000-0000-0000-0000-000000000003" &&
      output.workspace_managed_disk_identity.type == "SystemAssigned" &&
      output.workspace_storage_account_identity.principal_id == "00000000-0000-0000-0000-000000000004" &&
      output.workspace_storage_account_identity.tenant_id == "00000000-0000-0000-0000-000000000002" &&
      endswith(output.workspace_disk_encryption_set_id, "/diskEncryptionSets/dbw-disks")
    )
    error_message = "Discrete workspace response exports must preserve public output values."
  }
  assert {
    condition     = azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.keySource == "Default"
    error_message = "Without a DBFS key the persistent binding must explicitly request platform encryption."
  }
  assert {
    condition = (
      !contains(keys(azapi_resource.this.body.properties.parameters), "encryption") &&
      !contains(keys(azapi_resource.this.body.properties.parameters), "prepareEncryption")
    )
    error_message = "Without a DBFS key the workspace body must omit DBFS encryption parameters."
  }
  assert {
    condition     = output.onelake_targets["curated"].abfs_uri == "abfss://${uuidv5("dns", "workspace.example")}@test-region-onelake.dfs.fabric.microsoft.com/${uuidv5("dns", "item.example")}/Tables"
    error_message = "OneLake metadata must preserve canonical caller-selected ABFS URIs."
  }
}

run "onelake_requires_premium" {
  command = plan
  variables { sku = "standard" }
  expect_failures = [var.sku]
}

run "configurable_security_and_existing_resource_group" {
  command = plan
  variables {
    resource_group_resource_id            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-existing"
    no_public_ip                          = false
    default_storage_firewall_enabled      = false
    public_network_access_enabled         = false
    network_security_group_rules_required = "NoAzureDatabricksRules"
    lock                                  = { kind = "CanNotDelete", notes = "Protected workspace" }
  }
  assert {
    condition = (
      length(module.resource_group) == 0 &&
      azapi_resource.this.parent_id == var.resource_group_resource_id &&
      !azapi_resource.this.body.properties.parameters.enableNoPublicIp.value &&
      azapi_resource.this.body.properties.defaultStorageFirewall == "Disabled" &&
      azapi_resource.this.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.this.body.properties.requiredNsgRules == "NoAzureDatabricksRules"
    )
    error_message = "Approved exceptions and existing RG targeting must reach ARM."
  }
  assert {
    condition = (
      azapi_resource.lock[0].body.properties.level == "CanNotDelete" &&
      azapi_resource.lock[0].body.properties.notes == "Protected workspace" &&
      azapi_resource.lock[0].name == "lock-CanNotDelete" &&
      azapi_resource.lock[0].parent_id == azapi_resource.this.id &&
      length(modtm_telemetry.this) == 0
    )
    error_message = "Workspace locks must use actual ARM properties and telemetry must stay off."
  }
}

run "customer_managed_keys" {
  command = apply
  variables {
    databricks_customer_managed_keys = {
      dbfs_root_key_vault_key_id                      = "https://kv-test.vault.azure.net/keys/dbfs/dbfs-version"
      managed_disk_key_vault_key_id                   = "https://kv-test.vault.azure.net/keys/disks/disk-version"
      managed_disk_rotation_to_latest_version_enabled = true
      managed_services_key_vault_key_id               = "https://kv-test.vault.azure.net/keys/services/services-version"
    }
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.parameters.prepareEncryption.value &&
      azapi_resource.this.body.properties.encryption.entities.managedDisk.keyVaultProperties.keyName == "disks" &&
      azapi_resource.this.body.properties.encryption.entities.managedDisk.keyVaultProperties.keyVersion == "disk-version" &&
      azapi_resource.this.body.properties.encryption.entities.managedDisk.keyVaultProperties.keyVaultUri == "https://kv-test.vault.azure.net/" &&
      azapi_resource.this.body.properties.encryption.entities.managedDisk.rotationToLatestKeyVersionEnabled &&
      azapi_resource.this.body.properties.encryption.entities.managedServices.keySource == "Microsoft.Keyvault" &&
      azapi_resource.this.body.properties.encryption.entities.managedServices.keyVaultProperties.keyName == "services" &&
      azapi_resource.this.body.properties.encryption.entities.managedServices.keyVaultProperties.keyVersion == "services-version"
    )
    error_message = "Managed disk/services keys, versions and rotation must be represented in the ARM request."
  }
  assert {
    condition = (
      azapi_update_resource.dbfs_root_key.resource_id == azapi_resource.this.id &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.keySource == "Microsoft.Keyvault" &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.KeyName == "dbfs" &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.keyvaulturi == "https://kv-test.vault.azure.net" &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.keyversion == "dbfs-version"
    )
    error_message = "Root DBFS must be bound through the exact ARM parameters.encryption shape after workspace creation."
  }
  # Azure rejects parameters.encryption in a workspace create request with
  # InvalidEncryptionConfiguration (observed in a live deployment), so only the separate
  # binding may carry it.
  assert {
    condition     = !contains(keys(azapi_resource.this.body.properties.parameters), "encryption")
    error_message = "The workspace request must not configure root DBFS encryption; it is bound after creation."
  }
  assert {
    condition = (
      length(azapi_resource.dbfs_root_key_role_assignment) == 0 &&
      terraform_data.dbfs_root_key_grant_revision.input == null &&
      azapi_update_resource.dbfs_root_key.retry == null
    )
    error_message = "Without dbfs_root_key_role_assignment the module must not grant Key Vault access or add a retry default."
  }
}

run "dbfs_key_grant_precedes_binding" {
  command = apply
  variables {
    databricks_customer_managed_keys = {
      dbfs_root_key_role_assignment = {
        key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test"
      }
      dbfs_root_key_vault_key_id = "https://kv-test.vault.azure.net/keys/dbfs/dbfs-version"
    }
  }
  assert {
    condition = (
      length(azapi_resource.dbfs_root_key_role_assignment) == 1 &&
      azapi_resource.dbfs_root_key_role_assignment[0].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test/keys/dbfs" &&
      azapi_resource.dbfs_root_key_role_assignment[0].type == "Microsoft.Authorization/roleAssignments@2022-04-01" &&
      azapi_resource.dbfs_root_key_role_assignment[0].body.properties.principalId == "00000000-0000-0000-0000-000000000004" &&
      azapi_resource.dbfs_root_key_role_assignment[0].body.properties.principalType == "ServicePrincipal" &&
      azapi_resource.dbfs_root_key_role_assignment[0].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000009/providers/Microsoft.Authorization/roleDefinitions/e147488a-f6f5-4113-8e2d-b22465e65bf6" &&
      can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", azapi_resource.dbfs_root_key_role_assignment[0].name))
    )
    error_message = "The DBFS key grant must give the workspace storage identity Key Vault Crypto Service Encryption User on the DBFS key itself."
  }
  assert {
    condition = (
      terraform_data.dbfs_root_key_grant_revision.input == azapi_resource.dbfs_root_key_role_assignment[0].name &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.KeyName == "dbfs" &&
      azapi_update_resource.dbfs_root_key.retry.error_message_regex == tolist(["(?i)KeyVaultAuthenticationFailure", "(?i)authentication issue on the key ?vault", "(?i)ApplicationUpdateFail"]) &&
      azapi_update_resource.dbfs_root_key.retry.interval_seconds == 15 &&
      azapi_update_resource.dbfs_root_key.retry.max_interval_seconds == 60
    )
    error_message = "With a module-managed grant the binding must track the grant and retry Key Vault authorization failures while RBAC propagates."
  }
}

run "caller_retry_replaces_dbfs_grant_retry_default" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      dbfs_root_key_role_assignment = {
        key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test"
      }
      dbfs_root_key_vault_key_id = "https://kv-test.vault.azure.net/keys/dbfs"
    }
    retry = {
      error_message_regex = ["ScopeLocked"]
    }
  }
  assert {
    condition = (
      azapi_update_resource.dbfs_root_key.retry.error_message_regex == tolist(["ScopeLocked"]) &&
      azapi_resource.dbfs_root_key_role_assignment[0].retry.error_message_regex == tolist(["ScopeLocked"])
    )
    error_message = "A caller-supplied retry must replace the module's DBFS binding retry default (TFFR7)."
  }
}

run "dbfs_grant_requires_dbfs_key" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      dbfs_root_key_role_assignment = {
        key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test"
      }
      managed_disk_key_vault_key_id = "https://kv-test.vault.azure.net/keys/disks/disk-version"
    }
  }
  expect_failures = [var.databricks_customer_managed_keys]
}

run "dbfs_grant_rejects_invalid_vault_id" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      dbfs_root_key_role_assignment = {
        key_vault_resource_id = "kv-test"
      }
      dbfs_root_key_vault_key_id = "https://kv-test.vault.azure.net/keys/dbfs/dbfs-version"
    }
  }
  expect_failures = [var.databricks_customer_managed_keys]
}

run "dbfs_grant_rejects_vault_that_does_not_host_the_key" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      dbfs_root_key_role_assignment = {
        key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-other"
      }
      dbfs_root_key_vault_key_id = "https://kv-test.vault.azure.net/keys/dbfs/dbfs-version"
    }
  }
  expect_failures = [var.databricks_customer_managed_keys]
}

# The same state is reused: removing the key updates the binding rather than deleting it.
run "removing_dbfs_key_reverts_to_default" {
  command = apply
  assert {
    condition = (
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.keySource == "Default" &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.KeyName == null &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.keyvaulturi == null
    )
    error_message = "Removing DBFS CMK must send Default and clear the key fields."
  }
}

run "diagnostic_settings_forward_metrics_destination_type_and_enabled_flags" {
  command = plan
  variables {
    diagnostic_settings = {
      audit = {
        name                  = "diag-databricks"
        logs                  = [{ category = "accounts" }, { category = "clusters", enabled = false }]
        metrics               = [{ category = "AllMetrics", enabled = false }]
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
    }
  }
  assert {
    condition = (
      azapi_resource.diagnostic_settings["audit"].body.properties.logAnalyticsDestinationType == "Dedicated" &&
      azapi_resource.diagnostic_settings["audit"].body.properties.metrics[0].category == "AllMetrics" &&
      !azapi_resource.diagnostic_settings["audit"].body.properties.metrics[0].enabled &&
      length([for log in azapi_resource.diagnostic_settings["audit"].body.properties.logs : log if log.category == "clusters" && !log.enabled]) == 1 &&
      length([for log in azapi_resource.diagnostic_settings["audit"].body.properties.logs : log if log.category == "accounts" && log.enabled]) == 1 &&
      azapi_resource.diagnostic_settings["audit"].body.properties.workspaceId != null &&
      azapi_resource.diagnostic_settings["audit"].name == "diag-databricks"
    )
    error_message = "Dedicated, destination, categories and every enabled flag must reach ARM unchanged."
  }
}

run "diagnostic_settings_preserve_marketplace_destination" {
  command = plan
  variables {
    diagnostic_settings = {
      partner = {
        logs                            = [{ category_group = "allLogs" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
        log_analytics_destination_type  = "AzureDiagnostics"
      }
    }
  }
  assert {
    condition = (
      azapi_resource.diagnostic_settings["partner"].body.properties.marketplacePartnerId != null &&
      azapi_resource.diagnostic_settings["partner"].body.properties.logAnalyticsDestinationType == null &&
      azapi_resource.diagnostic_settings["partner"].body.properties.logs[0].categoryGroup == "allLogs" &&
      azapi_resource.diagnostic_settings["partner"].name == "diag-dbw-test-${sha256("partner")}"
    )
    error_message = "Marketplace/log groups must survive and AzureDiagnostics must become ARM null at the boundary."
  }
}

run "two_unnamed_diagnostics_are_distinct" {
  command = plan
  variables {
    diagnostic_settings = {
      first = {
        logs                  = [{ category = "accounts" }]
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
      second = {
        metrics               = [{ category = "AllMetrics", enabled = true }]
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
    }
  }
  assert {
    condition = (
      azapi_resource.diagnostic_settings["first"].name == "diag-dbw-test-${sha256("first")}" &&
      azapi_resource.diagnostic_settings["second"].name == "diag-dbw-test-${sha256("second")}" &&
      azapi_resource.diagnostic_settings["first"].name != azapi_resource.diagnostic_settings["second"].name &&
      azapi_resource.diagnostic_settings["second"].body.properties.metrics[0].enabled
    )
    error_message = "Unnamed diagnostic settings must have stable map-key-derived distinct names."
  }
}

run "duplicate_explicit_names_are_rejected" {
  command = plan
  variables {
    diagnostic_settings = {
      first = {
        name                            = "same-name"
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
      second = {
        name                            = "SAME-NAME"
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
    }
  }
  expect_failures = [var.diagnostic_settings]
}

run "explicit_generated_name_collision_is_rejected" {
  command = plan
  variables {
    diagnostic_settings = {
      first = {
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
      second = {
        name                            = "diag-dbw-test-${sha256("first")}"
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
    }
  }
  expect_failures = [var.diagnostic_settings]
}

run "empty_diagnostic_name_is_rejected" {
  command = plan
  variables {
    diagnostic_settings = {
      first = {
        name                            = ""
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
    }
  }
  expect_failures = [var.diagnostic_settings]
}

run "rejects_diagnostic_retention" {
  command = plan
  variables {
    diagnostic_settings = {
      retained = {
        logs                  = [{ category = "accounts", retention_policy = { enabled = true, days = 30 } }]
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
    }
  }
  expect_failures = [var.diagnostic_settings]
}

run "rejects_malformed_onelake_target" {
  command = plan
  variables {
    onelake_targets = {
      invalid = {
        endpoint_host       = "https://onelake.dfs.fabric.microsoft.com"
        fabric_item_id      = "not-a-guid"
        fabric_item_type    = "Lakehouse"
        fabric_workspace_id = uuidv5("dns", "workspace.example")
      }
    }
  }
  expect_failures = [var.onelake_targets]
}

run "rejects_versionless_managed_disk_key" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      managed_disk_key_vault_key_id = "https://kv-test.vault.azure.net/keys/disks"
    }
  }
  expect_failures = [var.databricks_customer_managed_keys]
}

run "rejects_versionless_managed_services_key" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      managed_services_key_vault_key_id = "https://kv-test.vault.azure.net/keys/services"
    }
  }
  expect_failures = [var.databricks_customer_managed_keys]
}

run "accepts_versionless_dbfs_root_key" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      dbfs_root_key_vault_key_id = "https://kv-test.vault.azure.net/keys/dbfs"
    }
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.parameters.prepareEncryption.value &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.KeyName == "dbfs" &&
      azapi_update_resource.dbfs_root_key.body.properties.parameters.encryption.value.keyversion == ""
    )
    error_message = "Versionless DBFS keys must use the API's empty key version."
  }
}

run "rejects_legacy_managed_disk_vault_id" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      managed_disk_key_vault_key_id      = "https://kv-test.vault.azure.net/keys/disks/v1"
      managed_disk_key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test"
    }
  }
  expect_failures = [var.databricks_customer_managed_keys]
}

run "rejects_legacy_managed_services_vault_id" {
  command = plan
  variables {
    databricks_customer_managed_keys = {
      managed_services_key_vault_key_id      = "https://kv-test.vault.azure.net/keys/services/v1"
      managed_services_key_vault_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test"
    }
  }
  expect_failures = [var.databricks_customer_managed_keys]
}

run "cross_subscription_resource_group_targets_both_resources" {
  command = plan
  variables {
    resource_group_resource_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-other-subscription"
  }
  assert {
    condition = (
      azapi_resource.this.parent_id == var.resource_group_resource_id &&
      local.resource_group_resource_id == var.resource_group_resource_id &&
      azapi_resource.this.body.properties.managedResourceGroupId == "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-databricks-managed-test"
    )
    error_message = "Workspace, Access Connector parent and managed RG must consistently retain the targeted subscription."
  }
}

run "infrastructure_encryption_false_preserves_legacy_body" {
  command = plan
  variables {
    infrastructure_encryption_enabled = false
  }
  assert {
    condition = (
      !contains(keys(azapi_resource.this.body.properties.parameters), "requireInfrastructureEncryption") &&
      !azapi_resource.this.replace_triggers_external_values.infrastructure_encryption_enabled
    )
    error_message = "False must retain the legacy omitted ARM parameter without an artificial migration replacement."
  }
}

run "azure_diagnostics_log_analytics_destination_is_null" {
  command = plan
  variables {
    diagnostic_settings = {
      shared = {
        logs                           = [{ category = "accounts", enabled = false }]
        metrics                        = [{ category = "AllMetrics" }]
        log_analytics_destination_type = "AzureDiagnostics"
        workspace_resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-test"
      }
    }
  }
  assert {
    condition = (
      azapi_resource.diagnostic_settings["shared"].body.properties.logAnalyticsDestinationType == null &&
      azapi_resource.diagnostic_settings["shared"].body.properties.workspaceId == var.diagnostic_settings["shared"].workspace_resource_id &&
      !azapi_resource.diagnostic_settings["shared"].body.properties.logs[0].enabled &&
      azapi_resource.diagnostic_settings["shared"].body.properties.metrics[0].enabled
    )
    error_message = "AzureDiagnostics must become ARM null without resetting Dedicated or changing logs/metrics."
  }
}

run "empty_and_long_map_keys_generate_valid_names" {
  command = plan
  variables {
    diagnostic_settings = {
      "" = {
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
      ("long/unsafe/${join("", [for index in range(300) : "x"])}") = {
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
    }
  }
  assert {
    condition = (
      length(distinct([for diagnostic in azapi_resource.diagnostic_settings : diagnostic.name])) == 2 &&
      alltrue([for diagnostic in azapi_resource.diagnostic_settings : length(diagnostic.name) <= 134 && can(regex("^diag-dbw-test-[a-f0-9]{64}$", diagnostic.name))])
    )
    error_message = "Empty, long and unsafe map keys must produce bounded, legal and distinct hashed names."
  }
}

run "oversized_explicit_diagnostic_name_is_rejected" {
  command = plan
  variables {
    diagnostic_settings = {
      first = {
        name                            = join("", [for index in range(261) : "x"])
        logs                            = [{ category = "accounts" }]
        marketplace_partner_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-monitor/providers/Microsoft.Marketplace/partners/partner-test"
      }
    }
  }
  expect_failures = [var.diagnostic_settings]
}

run "readonly_lock_preserves_custom_name" {
  command = plan
  variables {
    lock = { kind = "ReadOnly", name = "workspace-readonly" }
  }
  assert {
    condition = (
      azapi_resource.lock[0].name == "workspace-readonly" &&
      azapi_resource.lock[0].body.properties.level == "ReadOnly" &&
      azapi_resource.lock[0].body.properties.notes == "Cannot delete or modify the resource or its child resources."
    )
    error_message = "ReadOnly locks must preserve their custom names and default notes in ARM."
  }
}

run "rejects_unrelated_subnet_association" {
  command = plan
  variables {
    private_subnet_network_security_group_association_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-other/subnets/snet-other"
  }
  expect_failures = [azapi_resource.this]
}
