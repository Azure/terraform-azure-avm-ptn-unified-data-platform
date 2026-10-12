# Every run block maps these mocks explicitly through providers: a mock provider only
# attaches automatically to providers the module under test declares itself, and this
# module intentionally does not declare providers it never uses directly (TFNFR26).
# Without the mapping, providers needed only by composed dependencies can fall back
# to real providers instead of mocks.
mock_provider "azapi" {}
mock_provider "fabric" {}
mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "time" {}

variables {
  location = "westeurope"
}

run "fabric_capacity_and_onelake_composition" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
    random = random
    time   = time
  }

  command = plan

  variables {
    databricks_data_landing_zones = {}
    # The AVM CI sets TF_VAR_enable_telemetry=false for unit tests, which overrides
    # the variable default, so this run enables telemetry explicitly.
    enable_telemetry = true
    data_management_landing_zones = {
      shared = {
        capacity_administration_members = ["fabric-admin@example.com"]
        capacity_name                   = "fctest"
        capacity_sku_name               = "F2"
        enable_telemetry                = false
        location                        = "westeurope"
        resource_group_name             = "rg-fabric-test"
      }
    }
    fabric_data_landing_zones = {
      platform = {
        capacity_key        = "shared"
        domain_description  = "Platform data domain"
        domain_display_name = "Platform"
        workspaces = {
          management = {
            description  = "Platform management workspace"
            display_name = "Platform Management"
          }
        }
      }
    }
    tenant_id = uuidv5("dns", "tenant.example")
  }

  assert {
    condition     = data.fabric_capacity.this["shared"].display_name == "fctest"
    error_message = "The data landing zone capacity key must resolve through the matching Fabric capacity lookup."
  }

  assert {
    condition     = contains(keys(output.workspace_onelake_endpoints), "platform")
    error_message = "The root must expose OneLake endpoints for each Fabric data landing zone."
  }

  assert {
    condition     = contains(keys(output.workspace_onelake_endpoints["platform"]), "management")
    error_message = "The root must preserve workspace keys in the OneLake endpoint output."
  }

  assert {
    condition     = length(modtm_telemetry.telemetry) == 1
    error_message = "Root pattern telemetry must be created when enable_telemetry is true."
  }

  assert {
    condition     = local.main_location == var.location
    error_message = "Telemetry must use the caller's reporting location rather than an unknown region."
  }
}

run "global_telemetry_opt_out_with_child_defaults" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
    random = random
    time   = time
  }

  command = plan

  variables {
    databricks_data_landing_zones = {}
    enable_telemetry              = false
    data_management_landing_zones = {
      shared = {
        capacity_administration_members = ["fabric-admin@example.com"]
        capacity_name                   = "fctest"
        capacity_sku_name               = "F2"
        location                        = "westeurope"
        resource_group_name             = "rg-fabric-test"
      }
    }
    fabric_data_landing_zones = {
      platform = {
        capacity_key        = "shared"
        domain_description  = "Platform data domain"
        domain_display_name = "Platform"
        workspaces = {
          management = {
            description  = "Platform management workspace"
            display_name = "Platform Management"
          }
        }
      }
    }
    tenant_id = uuidv5("dns", "tenant.example")
  }

  assert {
    condition     = length(modtm_telemetry.telemetry) == 0
    error_message = "Global telemetry opt-out must disable root telemetry while child telemetry flags retain their true defaults."
  }
}

run "rejects_missing_capacity_key" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
    random = random
    time   = time
  }

  command = plan

  variables {
    databricks_data_landing_zones = {}
    enable_telemetry              = false
    data_management_landing_zones = {
      shared = {
        capacity_administration_members = ["fabric-admin@example.com"]
        capacity_name                   = "fctest"
        capacity_sku_name               = "F2"
        enable_telemetry                = false
        location                        = "westeurope"
        resource_group_name             = "rg-fabric-test"
      }
    }
    fabric_data_landing_zones = {
      platform = {
        capacity_key        = "missing"
        domain_description  = "Platform data domain"
        domain_display_name = "Platform"
        workspaces = {
          management = {
            description  = "Platform management workspace"
            display_name = "Platform Management"
          }
        }
      }
    }
    tenant_id = uuidv5("dns", "tenant.example")
  }

  expect_failures = [var.fabric_data_landing_zones]

  assert {
    condition     = length(modtm_telemetry.telemetry) == 0
    error_message = "Root pattern telemetry must support explicit opt-out."
  }
}

run "rejects_legacy_vault_id_hints_at_the_root" {
  command = plan
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
    random = random
    time   = time
  }

  variables {
    enable_telemetry = false
    tenant_id        = uuidv5("dns", "tenant.example")
    data_management_landing_zones = {
      shared = {
        capacity_administration_members = ["fabric-admin@example.com"]
        capacity_name                   = "fctest"
        capacity_sku_name               = "F2"
        location                        = "westeurope"
        resource_group_name             = "rg-fabric-test"
      }
    }
    fabric_data_landing_zones = {
      platform = {
        capacity_key        = "shared"
        domain_description  = "Test domain"
        domain_display_name = "Test"
        workspaces = {
          management = {
            description  = "Test workspace"
            display_name = "Test"
          }
        }
      }
    }
    databricks_data_landing_zones = {
      platform = {
        access_connector_name                                = "ac-test"
        location                                             = "westeurope"
        managed_resource_group_name                          = "rg-dbw-managed-test"
        private_subnet_name                                  = "private"
        private_subnet_network_security_group_association_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/private"
        public_subnet_name                                   = "public"
        public_subnet_network_security_group_association_id  = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/public"
        resource_group_name                                  = "rg-dbw-test"
        sku                                                  = "premium"
        virtual_network_id                                   = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet"
        workspace_name                                       = "dbw-test"
        customer_managed_key = {
          managed_disk_key_vault_key_id      = "https://kv-test.vault.azure.net/keys/disks/${uuidv5("dns", "disk-key.example")}"
          managed_disk_key_vault_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test"
        }
      }
    }
  }

  expect_failures = [var.databricks_data_landing_zones]
}
run "databricks_dbfs_key_grant_plans_through_the_root" {
  command = plan
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
    random = random
    time   = time
  }

  variables {
    enable_telemetry = false
    tenant_id        = uuidv5("dns", "tenant.example")
    data_management_landing_zones = {
      shared = {
        capacity_administration_members = ["fabric-admin@example.com"]
        capacity_name                   = "fctest"
        capacity_sku_name               = "F2"
        location                        = "westeurope"
        resource_group_name             = "rg-fabric-test"
      }
    }
    fabric_data_landing_zones = {
      platform = {
        capacity_key        = "shared"
        domain_description  = "Test domain"
        domain_display_name = "Test"
        workspaces = {
          management = {
            description  = "Test workspace"
            display_name = "Test"
          }
        }
      }
    }
    databricks_data_landing_zones = {
      platform = {
        access_connector_name                                = "ac-test"
        location                                             = "westeurope"
        managed_resource_group_name                          = "rg-dbw-managed-test"
        private_subnet_name                                  = "private"
        private_subnet_network_security_group_association_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/private"
        public_subnet_name                                   = "public"
        public_subnet_network_security_group_association_id  = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/public"
        resource_group_name                                  = "rg-dbw-test"
        resource_group_resource_id                           = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-dbw-test"
        sku                                                  = "premium"
        virtual_network_id                                   = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet"
        workspace_name                                       = "dbw-test"
        customer_managed_key = {
          dbfs_root_key_role_assignment = {
            key_vault_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-keys/providers/Microsoft.KeyVault/vaults/kv-test"
          }
          dbfs_root_key_vault_key_id = "https://kv-test.vault.azure.net/keys/dbfs/${uuidv5("dns", "dbfs-key.example")}"
        }
      }
    }
  }

  assert {
    condition     = contains(keys(output.databricks_data_landing_zones), "platform")
    error_message = "A Databricks zone that asks the module to grant root DBFS key access must plan through the root without a dependency cycle."
  }
}

run "rejects_invalid_dbfs_key_grant_vault_at_the_root" {
  command = plan
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
    random = random
    time   = time
  }

  variables {
    enable_telemetry = false
    tenant_id        = uuidv5("dns", "tenant.example")
    data_management_landing_zones = {
      shared = {
        capacity_administration_members = ["fabric-admin@example.com"]
        capacity_name                   = "fctest"
        capacity_sku_name               = "F2"
        location                        = "westeurope"
        resource_group_name             = "rg-fabric-test"
      }
    }
    fabric_data_landing_zones = {
      platform = {
        capacity_key        = "shared"
        domain_description  = "Test domain"
        domain_display_name = "Test"
        workspaces = {
          management = {
            description  = "Test workspace"
            display_name = "Test"
          }
        }
      }
    }
    databricks_data_landing_zones = {
      platform = {
        access_connector_name                                = "ac-test"
        location                                             = "westeurope"
        managed_resource_group_name                          = "rg-dbw-managed-test"
        private_subnet_name                                  = "private"
        private_subnet_network_security_group_association_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/private"
        public_subnet_name                                   = "public"
        public_subnet_network_security_group_association_id  = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/public"
        resource_group_name                                  = "rg-dbw-test"
        sku                                                  = "premium"
        virtual_network_id                                   = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet"
        workspace_name                                       = "dbw-test"
        customer_managed_key = {
          dbfs_root_key_role_assignment = {
            key_vault_resource_id = "kv-test"
          }
          dbfs_root_key_vault_key_id = "https://kv-test.vault.azure.net/keys/dbfs"
        }
      }
    }
  }

  expect_failures = [var.databricks_data_landing_zones]
}
