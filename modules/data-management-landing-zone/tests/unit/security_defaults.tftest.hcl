# Every run block maps these mocks explicitly through providers: a mock provider only
# attaches automatically to providers the module under test declares itself, and this
# module intentionally does not declare providers it never uses directly (TFNFR26).
# Without the mapping, providers needed only by composed dependencies (for example
# random, used internally by pinned AVM resource modules) fall back to the real provider
# instead of the mock.
mock_provider "azapi" {}
mock_provider "modtm" {}
mock_provider "random" {}

run "composes_capacity" {
  providers = {
    azapi  = azapi
    modtm  = modtm
    random = random
  }

  command = plan

  variables {
    capacity_administration_members = ["fabric-admin@example.com"]
    capacity_name                   = "fctest"
    capacity_sku_name               = "F2"
    location                        = "westeurope"
    resource_group_name             = "rg-fabric-test"
  }

  assert {
    condition     = module.capacity.name == "fctest"
    error_message = "The DMLZ must compose the requested Fabric capacity."
  }
}

run "existing_resource_group_and_lock" {
  providers = {
    azapi  = azapi
    modtm  = modtm
    random = random
  }

  command = plan

  variables {
    capacity_administration_members = [uuidv5("dns", "capacity-admin.example")]
    capacity_name                   = "fctest"
    capacity_sku_name               = "F2"
    enable_telemetry                = false
    location                        = "westeurope"
    lock                            = { kind = "CanNotDelete" }
    resource_group_name             = "ignored"
    resource_group_resource_id      = "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-existing"
  }

  assert {
    condition     = length(module.resource_group) == 0
    error_message = "Supplying an existing resource group ID must prevent resource group creation."
  }

  assert {
    condition     = local.resource_group_resource_id == "/subscriptions/${uuidv5("dns", "subscription.example")}/resourceGroups/rg-existing"
    error_message = "The existing resource group ID must be passed to the composed capacity module."
  }
}

run "rejects_invalid_capacity_name" {
  providers = {
    azapi  = azapi
    modtm  = modtm
    random = random
  }

  command = plan

  variables {
    capacity_administration_members = ["fabric-admin@example.com"]
    capacity_name                   = "INVALID-NAME"
    capacity_sku_name               = "F2"
    enable_telemetry                = false
    location                        = "westeurope"
    resource_group_name             = "rg-fabric-test"
  }

  expect_failures = [var.capacity_name]
}

run "rejects_invalid_capacity_sku" {
  providers = {
    azapi  = azapi
    modtm  = modtm
    random = random
  }

  command = plan

  variables {
    capacity_administration_members = ["fabric-admin@example.com"]
    capacity_name                   = "fctest"
    capacity_sku_name               = "P1"
    enable_telemetry                = false
    location                        = "westeurope"
    resource_group_name             = "rg-fabric-test"
  }

  expect_failures = [var.capacity_sku_name]
}