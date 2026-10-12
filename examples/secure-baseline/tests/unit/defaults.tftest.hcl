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
}
mock_provider "fabric" {}
mock_provider "random" {}
mock_provider "time" {}

override_resource {
  target          = azapi_resource.connectivity_resource_group
  override_during = plan
  values = {
    id = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33/resourceGroups/rg-udp-connectivity-test"
  }
}

override_resource {
  target          = azapi_resource.virtual_network
  override_during = plan
  values = {
    id = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33/resourceGroups/rg-udp-connectivity-test/providers/Microsoft.Network/virtualNetworks/vnet-udp-test"
  }
}

override_resource {
  target          = azapi_resource.fabric_private_dns_zone
  override_during = plan
  values = {
    id = "/subscriptions/479115e6-faed-5bf2-a257-43b56737cc33/resourceGroups/rg-udp-connectivity-test/providers/Microsoft.Network/privateDnsZones/privatelink.fabric.microsoft.com"
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
    condition     = length(azapi_resource.virtual_network) == 1 && length(azapi_resource.fabric_private_dns_zone_link) == 1
    error_message = "By default the example must create the network and private DNS prerequisites for workspace private link itself."
  }

  assert {
    condition     = azapi_resource.fabric_private_dns_zone_link[0].body.properties.virtualNetwork.id == azapi_resource.virtual_network[0].id
    error_message = "The private DNS zone must be linked to the example virtual network so the private endpoint resolves privately."
  }

  assert {
    condition     = local.capacity_administration_members == toset(["5f2b7c1e-9a3d-4e8f-8b6a-2c1d0e9f7a61"])
    error_message = "Without input, the deploying identity must become the Fabric capacity administrator."
  }

  assert {
    condition     = length(local.domain_role_assignments) == 0 && length(local.workspace_role_assignments) == 0
    error_message = "Without group object IDs, the example must not create group role assignments."
  }
}

run "private_link_disabled_creates_no_network_prerequisites" {
  providers = {
    azapi  = azapi
    fabric = fabric
    random = random
    time   = time
  }

  command = plan

  variables {
    enable_workspace_private_link = false
  }

  assert {
    condition     = length(azapi_resource.connectivity_resource_group) == 0 && length(azapi_resource.virtual_network) == 0 && length(azapi_resource.fabric_private_dns_zone) == 0
    error_message = "Disabling workspace private link must not create the example's network prerequisites."
  }
}

run "group_role_assignments_are_opt_in" {
  providers = {
    azapi  = azapi
    fabric = fabric
    random = random
    time   = time
  }

  command = plan

  variables {
    domain_administration_group_object_id    = "8d0c3a7e-1b2f-4c5d-9e6f-7a8b9c0d1e2f"
    workspace_administration_group_object_id = "3e4f5a6b-7c8d-4e9f-a0b1-c2d3e4f5a6b7"
  }

  assert {
    condition     = local.domain_role_assignments["Admins"][0].id == "8d0c3a7e-1b2f-4c5d-9e6f-7a8b9c0d1e2f"
    error_message = "A supplied domain administration group must be assigned the domain Admins role."
  }

  assert {
    condition     = local.workspace_role_assignments["administrators"].principal.id == "3e4f5a6b-7c8d-4e9f-a0b1-c2d3e4f5a6b7" && local.workspace_role_assignments["administrators"].role == "Admin"
    error_message = "A supplied workspace administration group must be assigned the workspace Admin role."
  }
}
