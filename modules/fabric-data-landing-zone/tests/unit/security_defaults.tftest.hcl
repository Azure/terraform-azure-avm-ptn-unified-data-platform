mock_provider "azapi" {}
mock_provider "fabric" {}
mock_provider "modtm" {}

variables {
  location = "westeurope"
}

run "workspace_network_controls_are_opt_in" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      platform = {
        display_name = "Test Platform"
        description  = "Test platform workspace"
      }
    }
  }

  assert {
    condition     = length(fabric_workspace_network_communication_policy.this) == 0
    error_message = "Workspace network communication policy must not be created unless network restrictions are enabled."
  }

  assert {
    condition     = length(fabric_workspace_outbound_cloud_connection_rules.this) == 0
    error_message = "Cloud connection restrictions must not be created unless network restrictions are enabled."
  }

  assert {
    condition     = length(fabric_workspace_outbound_gateway_rules.this) == 0
    error_message = "Gateway restrictions must not be created unless network restrictions are enabled."
  }

  assert {
    condition     = length(fabric_workspace_git_outbound_policy.this) == 0
    error_message = "Git outbound policy must not be created unless network restrictions are enabled; Fabric's own platform default is Allow."
  }
}

run "enabled_workspace_networks_fail_closed" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      platform = {
        display_name                = "Test Platform"
        description                 = "Test platform workspace"
        enable_network_restrictions = true
      }
    }
  }

  assert {
    condition     = fabric_workspace_network_communication_policy.this["platform"].inbound.public_access_rules.default_action == "Allow"
    error_message = "Inbound access must remain available until private-link readiness is explicitly acknowledged."
  }

  assert {
    condition     = fabric_workspace_network_communication_policy.this["platform"].outbound.public_access_rules.default_action == "Deny"
    error_message = "Enabled outbound public-access protection must default to Deny."
  }

  assert {
    condition     = fabric_workspace_outbound_cloud_connection_rules.this["platform"].default_action == "Deny"
    error_message = "Enabled cloud connection protection must default to Deny."
  }
}

run "git_deny_override_is_supported" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      restricted = {
        display_name                = "Restricted Workspace"
        description                 = "Workspace where Git integration is prohibited"
        enable_network_restrictions = true
        git_outbound_default_action = "Deny"
      }
    }
  }

  assert {
    condition     = fabric_workspace_git_outbound_policy.this["restricted"].default_action == "Deny"
    error_message = "A workspace must be able to override the Git outbound policy to Deny."
  }
}

run "outbound_allowlists_require_network_restrictions" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      platform = {
        display_name = "Test Platform"
        description  = "Test platform workspace"
        allowed_gateways = [{
          id = uuidv5("dns", "gateway.example")
        }]
      }
    }
  }

  expect_failures = [var.workspaces]
}

run "lockdown_requires_private_link" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      platform = {
        display_name                    = "Test Platform"
        description                     = "Test platform workspace"
        enable_network_restrictions     = true
        private_link_ready_for_lockdown = true
      }
    }
  }

  expect_failures = [var.workspaces]
}

run "verified_private_link_enables_lockdown" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      platform = {
        display_name                    = "Test Platform"
        description                     = "Test platform workspace"
        enable_network_restrictions     = true
        private_link_ready_for_lockdown = true
        private_link = {
          location                     = "westeurope"
          private_dns_zone_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.fabric.microsoft.com"
          private_endpoint_name        = "pep-fabric-test"
          private_link_service_name    = "pls-fabric-test"
          resource_group_resource_id   = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity"
          subnet_resource_id           = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-connectivity/subnets/snet-private-endpoints"
        }
      }
    }
  }

  assert {
    condition     = fabric_workspace_network_communication_policy.this["platform"].inbound.public_access_rules.default_action == "Deny"
    error_message = "Verified workspace private link must enable inbound public-access denial."
  }
}

run "customer_managed_key_requires_preview_opt_in" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      platform = {
        display_name = "Test Platform"
        description  = "Test platform workspace"
        customer_managed_key = {
          key_identifier = "https://kv-test.vault.azure.net/keys/fabric-cmk/"
        }
      }
    }
  }

  expect_failures = [var.workspaces]
}

run "customer_managed_key_creates_workspace_encryption_when_opted_in" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id                 = uuidv5("dns", "capacity.example")
    domain_description                  = "Test domain"
    domain_display_name                 = "Test"
    tenant_id                           = uuidv5("dns", "tenant.example")
    enable_preview_workspace_encryption = true
    workspaces = {
      platform = {
        display_name = "Test Platform"
        description  = "Test platform workspace"
        customer_managed_key = {
          key_identifier = "https://kv-test.vault.azure.net/keys/fabric-cmk/"
        }
      }
      unencrypted = {
        display_name = "Unencrypted Workspace"
        description  = "Workspace without customer_managed_key configured"
      }
    }
  }

  assert {
    condition     = length(fabric_workspace_encryption.this) == 1
    error_message = "fabric_workspace_encryption must be created only for the workspace with customer_managed_key configured, not for every workspace."
  }

  assert {
    condition     = fabric_workspace_encryption.this["platform"].encryption_details.key_identifier == "https://kv-test.vault.azure.net/keys/fabric-cmk/"
    error_message = "The workspace encryption resource must use the supplied key_identifier."
  }
}

run "composite_keys_do_not_collide_across_ambiguous_boundaries" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  # Regression test: workspace key "sales-west" with role assignment key "reader" must not
  # collide with workspace key "sales" and role assignment key "west-reader" (and likewise for
  # managed private endpoints). A naive "${workspace_key}-${assignment_key}" string join would
  # produce the identical composite key "sales-west-reader" for both, silently dropping one
  # entry via merge(). Both workspaces' assignments and endpoints must all be present.
  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      sales-west = {
        display_name = "Sales West"
        description  = "Ambiguous-boundary workspace 1"
        role_assignments = {
          reader = {
            principal = {
              id   = uuidv5("dns", "sales-west-reader.example")
              type = "Group"
            }
            role = "Viewer"
          }
        }
        managed_private_endpoints = {
          reader = {
            name                            = "mpe-sales-west-reader"
            target_private_link_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-target/providers/Microsoft.Storage/storageAccounts/stsaleswest"
          }
        }
      }
      sales = {
        display_name = "Sales"
        description  = "Ambiguous-boundary workspace 2"
        role_assignments = {
          west-reader = {
            principal = {
              id   = uuidv5("dns", "sales-west-reader-2.example")
              type = "Group"
            }
            role = "Viewer"
          }
        }
        managed_private_endpoints = {
          west-reader = {
            name                            = "mpe-sales-west-reader-2"
            target_private_link_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-target/providers/Microsoft.Storage/storageAccounts/stsales"
          }
        }
      }
    }
  }

  assert {
    condition     = length(fabric_workspace_role_assignment.this) == 2
    error_message = "Both workspaces' role assignments must be created; an ambiguous key collision would silently drop one."
  }

  assert {
    condition     = length(fabric_workspace_managed_private_endpoint.this) == 2
    error_message = "Both workspaces' managed private endpoints must be created; an ambiguous key collision would silently drop one."
  }

  assert {
    condition     = fabric_workspace_role_assignment.this[jsonencode(["sales-west", "reader"])].principal.id == uuidv5("dns", "sales-west-reader.example")
    error_message = "The 'sales-west' workspace's 'reader' role assignment must resolve to the 'sales-west' entry, not the 'sales' workspace's 'west-reader' entry."
  }

  assert {
    condition     = fabric_workspace_role_assignment.this[jsonencode(["sales", "west-reader"])].principal.id == uuidv5("dns", "sales-west-reader-2.example")
    error_message = "The 'sales' workspace's 'west-reader' role assignment must resolve to the 'sales' entry, not the 'sales-west' workspace's 'reader' entry."
  }
}
run "private_link_service_uses_requested_resource_group" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    tags                = { environment = "test", owner = "platform-team" }
    workspaces = {
      platform = {
        display_name = "Test Platform"
        description  = "Test platform workspace"
        private_link = {
          location                     = "westeurope"
          private_dns_zone_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.fabric.microsoft.com"
          private_endpoint_name        = "pep-fabric-test"
          private_link_service_name    = "pls-fabric-test"
          resource_group_resource_id   = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity"
          subnet_resource_id           = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-connectivity/subnets/snet-private-endpoints"
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.workspace_private_link_service["platform"].parent_id == "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity"
    error_message = "The private-link service must be created in the requested resource group."
  }

  assert {
    condition     = length(azapi_resource.workspace_private_endpoint) == 1
    error_message = "Exactly one private endpoint must be created for the workspace that requests private link."
  }

  assert {
    condition     = azapi_resource.workspace_private_endpoint["platform"].body.properties.subnet.id == var.workspaces["platform"].private_link.subnet_resource_id
    error_message = "The private endpoint must use the requested subnet."
  }

  assert {
    condition     = azapi_resource.workspace_private_endpoint["platform"].tags == var.tags && azapi_resource.workspace_private_link_service["platform"].tags == var.tags
    error_message = "Both Azure private-link resources must preserve the standard module tags."
  }

  assert {
    condition     = azapi_resource.workspace_private_dns_zone_group["platform"].body.properties.privateDnsZoneConfigs[0].properties.privateDnsZoneId == var.workspaces["platform"].private_link.private_dns_zone_resource_id
    error_message = "The endpoint DNS zone group must reference the requested shared Fabric DNS zone."
  }

}

run "rejects_distinct_legacy_private_link_tags" {
  command = plan
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }
  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    tags                = { owner = "platform-team" }
    workspaces = {
      platform = {
        display_name = "Test"
        description  = "Test"
        private_link = {
          location                     = "westeurope"
          private_dns_zone_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.fabric.microsoft.com"
          private_endpoint_name        = "pep-fabric-test"
          private_link_service_name    = "pls-fabric-test"
          resource_group_resource_id   = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity"
          subnet_resource_id           = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-connectivity/subnets/snet-private-endpoints"
          tags                         = { owner = "different-owner" }
        }
      }
    }
  }
  expect_failures = [var.workspaces]
}

run "cross_subscription_private_link_targets_preserve_full_ids" {
  providers = {
    azapi  = azapi
    fabric = fabric
    modtm  = modtm
  }

  command = plan

  variables {
    default_capacity_id = uuidv5("dns", "capacity.example")
    domain_description  = "Test domain"
    domain_display_name = "Test"
    tenant_id           = uuidv5("dns", "tenant.example")
    workspaces = {
      platform = {
        display_name = "Test Platform"
        description  = "Test platform workspace"
        private_link = {
          location                     = "westeurope"
          private_dns_zone_resource_id = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.fabric.microsoft.com"
          private_endpoint_name        = "pep-fabric-test"
          private_link_service_name    = "pls-fabric-test"
          resource_group_resource_id   = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-connectivity"
          subnet_resource_id           = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-connectivity/subnets/snet-private-endpoints"
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.workspace_private_link_service["platform"].parent_id == "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-connectivity"
    error_message = "The private-link service must preserve the resource-group subscription from the supplied full ID."
  }

  assert {
    condition     = azapi_resource.workspace_private_endpoint["platform"].parent_id == azapi_resource.workspace_private_link_service["platform"].parent_id
    error_message = "The private endpoint and private-link service must target the same supplied resource group, not the ambient subscription."
  }
}
