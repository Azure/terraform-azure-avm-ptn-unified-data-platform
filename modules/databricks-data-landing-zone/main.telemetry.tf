resource "modtm_telemetry" "this" {
  count = var.enable_telemetry ? 1 : 0

  tags = {
    avm_module_source  = provider::modtm::module_source(path.module)
    avm_module_version = provider::modtm::module_version(path.module)
    location           = var.location
  }
}
