# Real-Azure integration test for root DBFS customer-managed keys; see docs/e2e-testing.md.
# It deploys a VNet-injected premium workspace, so it needs credentials that can create
# resource groups, Key Vaults and role assignments, and takes about 15 minutes. Terraform
# destroys everything afterwards; the purge-protected vault stays soft-deleted for 7 days.
# Run it with `avm test integration`. Change the region in the prerequisites run.

run "prerequisites" {
  command = apply

  module {
    source = "../../tests/fixtures/databricks-dbfs-prerequisites"
  }

  variables {
    location = "swedencentral"
  }
}

# One apply prepares the workspace, grants its new storage identity access to the key and
# binds the key. Without the grant between those steps the binding fails.
run "bind_dbfs_key_in_one_apply" {
  command = apply

  variables {
    access_connector_name                                = "dbac-udp-dbfs-it-${run.prerequisites.name_suffix}"
    enable_telemetry                                     = false
    location                                             = run.prerequisites.location
    managed_resource_group_name                          = "rg-udp-dbfs-it-${run.prerequisites.name_suffix}-managed"
    private_subnet_name                                  = "snet-dbw-private"
    private_subnet_network_security_group_association_id = run.prerequisites.private_subnet_id
    public_subnet_name                                   = "snet-dbw-public"
    public_subnet_network_security_group_association_id  = run.prerequisites.public_subnet_id
    resource_group_name                                  = run.prerequisites.resource_group_name
    resource_group_resource_id                           = run.prerequisites.resource_group_id
    sku                                                  = "premium"
    virtual_network_id                                   = run.prerequisites.virtual_network_id
    workspace_name                                       = "dbw-udp-dbfs-it-${run.prerequisites.name_suffix}"
    databricks_customer_managed_keys = {
      dbfs_root_key_role_assignment = {
        key_vault_resource_id = run.prerequisites.key_vault_id
      }
      dbfs_root_key_vault_key_id = run.prerequisites.dbfs_key_url
    }
    tags = {
      purpose = "avm-integration-test"
    }
  }

  assert {
    condition     = length(azapi_resource.dbfs_root_key_role_assignment) == 1
    error_message = "The module must grant the workspace storage identity access to the root DBFS key."
  }
}

run "verify_binding" {
  command = plan

  module {
    source = "../../tests/fixtures/databricks-dbfs-verify"
  }

  variables {
    workspace_id = run.bind_dbfs_key_in_one_apply.workspace_id
  }

  assert {
    condition     = output.workspace_key_source == "microsoft.keyvault" && output.workspace_key_name == "dbfs"
    error_message = "The workspace must report the root DBFS customer-managed key after one apply."
  }

  assert {
    condition     = output.storage_key_source == "microsoft.keyvault" && output.storage_key_name == "dbfs"
    error_message = "The root DBFS storage account must use the customer-managed key after one apply."
  }
}

# A later update of azapi_resource.this is a full PUT without parameters.encryption. The
# live key must survive it.
run "workspace_update_keeps_dbfs_key" {
  command = apply

  variables {
    access_connector_name                                = "dbac-udp-dbfs-it-${run.prerequisites.name_suffix}"
    enable_telemetry                                     = false
    location                                             = run.prerequisites.location
    managed_resource_group_name                          = "rg-udp-dbfs-it-${run.prerequisites.name_suffix}-managed"
    private_subnet_name                                  = "snet-dbw-private"
    private_subnet_network_security_group_association_id = run.prerequisites.private_subnet_id
    public_subnet_name                                   = "snet-dbw-public"
    public_subnet_network_security_group_association_id  = run.prerequisites.public_subnet_id
    resource_group_name                                  = run.prerequisites.resource_group_name
    resource_group_resource_id                           = run.prerequisites.resource_group_id
    sku                                                  = "premium"
    virtual_network_id                                   = run.prerequisites.virtual_network_id
    workspace_name                                       = "dbw-udp-dbfs-it-${run.prerequisites.name_suffix}"
    databricks_customer_managed_keys = {
      dbfs_root_key_role_assignment = {
        key_vault_resource_id = run.prerequisites.key_vault_id
      }
      dbfs_root_key_vault_key_id = run.prerequisites.dbfs_key_url
    }
    tags = {
      purpose  = "avm-integration-test"
      revision = "2"
    }
  }

  assert {
    condition     = azapi_resource.this.tags["revision"] == "2"
    error_message = "The workspace update must reach Azure."
  }
}

run "verify_binding_after_update" {
  command = plan

  module {
    source = "../../tests/fixtures/databricks-dbfs-verify"
  }

  variables {
    workspace_id = run.bind_dbfs_key_in_one_apply.workspace_id
  }

  assert {
    condition     = output.workspace_key_source == "microsoft.keyvault" && output.workspace_key_name == "dbfs"
    error_message = "The workspace must still report the root DBFS customer-managed key after a workspace update."
  }

  assert {
    condition     = output.storage_key_source == "microsoft.keyvault" && output.storage_key_name == "dbfs"
    error_message = "The root DBFS storage account must still use the customer-managed key after a workspace update."
  }
}
