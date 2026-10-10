# avm test e2e applies every example without any input, so this suite plans the example
# with its defaults only. Every run block maps the mocks explicitly through providers: a
# mock provider only attaches automatically to providers the configuration under test
# declares itself, and providers such as hashicorp/time are required only by the pattern
# module, not by this example. The example's own AzAPI resources receive realistic IDs
# because the pattern module validates the resource IDs it is given.
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      object_id                = "5f2b7c1e-9a3d-4e8f-8b6a-2c1d0e9f7a61"
      subscription_id          = "479115e6-faed-5bf2-a257-43b56737cc33"
      subscription_resource_id = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33"
      tenant_id                = "6c8f1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5b"
    }
  }
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        log_categories = ["accounts", "clusters", "dbfs", "jobs", "notebook", "ssh"]
      }
    }
  }
}
mock_provider "fabric" {}
mock_provider "random" {}
mock_provider "time" {}

override_resource {
  target          = azapi_resource.network_resource_group
  override_during = plan
  values = {
    id = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33/resourceGroups/rg-udp-dbw-network-test"
  }
}

override_resource {
  target          = azapi_resource.virtual_network
  override_during = plan
  values = {
    id = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33/resourceGroups/rg-udp-dbw-network-test/providers/Microsoft.Network/virtualNetworks/vnet-udp-dbw-test"
  }
}

override_resource {
  target          = azapi_resource.log_analytics_workspace
  override_during = plan
  values = {
    id = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33/resourceGroups/rg-udp-dbw-network-test/providers/Microsoft.OperationalInsights/workspaces/log-udp-test"
  }
}

run "plans_with_defaults_only" {
  providers = {
    azapi  = azapi
    fabric = fabric
    random = random
    time   = time
  }

  command = plan

  assert {
    condition = alltrue([
      for subnet in azapi_resource.virtual_network.body.properties.subnets :
      subnet.properties.delegations[0].properties.serviceName == "Microsoft.Databricks/workspaces"
    ]) && length(azapi_resource.virtual_network.body.properties.subnets) == 2
    error_message = "The example must create the two dedicated subnets delegated to Microsoft.Databricks/workspaces that VNet injection requires."
  }

  assert {
    condition     = length(azapi_resource.log_analytics_workspace) == 1
    error_message = "Without an existing Log Analytics workspace ID, the example must create one for Databricks diagnostics."
  }

  assert {
    condition     = local.databricks_diagnostic_settings["platform"].workspace_resource_id == azapi_resource.log_analytics_workspace[0].id
    error_message = "Databricks diagnostics must be sent to the example's Log Analytics workspace by default."
  }

  assert {
    condition     = toset([for log in local.databricks_diagnostic_settings["platform"].logs : log.category]) == toset(["accounts", "clusters", "dbfs", "jobs"])
    error_message = "diagnostic_log_categories must reach the module as populated logs, not be silently dropped by an attribute-name mismatch."
  }

  assert {
    condition     = local.capacity_administration_members == toset(["5f2b7c1e-9a3d-4e8f-8b6a-2c1d0e9f7a61"])
    error_message = "Without input, the deploying identity must become the Fabric capacity administrator."
  }
}

run "existing_log_analytics_workspace_is_used_when_supplied" {
  providers = {
    azapi  = azapi
    fabric = fabric
    random = random
    time   = time
  }

  command = plan

  variables {
    log_analytics_workspace_id   = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-central"
    diagnostic_metric_categories = ["AllMetrics"]
  }

  assert {
    condition     = length(azapi_resource.log_analytics_workspace) == 0
    error_message = "Supplying log_analytics_workspace_id must not create a second Log Analytics workspace."
  }

  assert {
    condition     = local.databricks_diagnostic_settings["platform"].workspace_resource_id == var.log_analytics_workspace_id
    error_message = "log_analytics_workspace_id must reach the module as workspace_resource_id."
  }

  assert {
    condition     = length(local.databricks_diagnostic_settings["platform"].metrics) == 1
    error_message = "diagnostic_metric_categories must reach the module as populated metrics, not be silently dropped by an attribute-name mismatch."
  }
}
