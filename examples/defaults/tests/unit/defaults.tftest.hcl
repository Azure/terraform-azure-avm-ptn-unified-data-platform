# avm test e2e applies every example without any input, so this suite plans the example
# with its defaults only. Every run block maps the mocks explicitly through providers: a
# mock provider only attaches automatically to providers the configuration under test
# declares itself, and providers such as hashicorp/time are required only by the pattern
# module, not by this example.
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

run "plans_with_defaults_only" {
  providers = {
    azapi  = azapi
    fabric = fabric
    random = random
    time   = time
  }

  command = plan

  assert {
    condition     = local.capacity_administration_members == toset(["5f2b7c1e-9a3d-4e8f-8b6a-2c1d0e9f7a61"])
    error_message = "Without input, the deploying identity must become the Fabric capacity administrator so it can assign the example workspace to the capacity."
  }
}

run "explicit_capacity_administrators_override_the_default" {
  providers = {
    azapi  = azapi
    fabric = fabric
    random = random
    time   = time
  }

  command = plan

  variables {
    capacity_administration_members = ["fabric-admin@example.com"]
  }

  assert {
    condition     = local.capacity_administration_members == toset(["fabric-admin@example.com"])
    error_message = "A supplied capacity_administration_members value must replace the deploying-identity default."
  }
}
