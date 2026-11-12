locals {
  data_management_landing_zone_telemetry = {
    for key, zone in var.data_management_landing_zones : key => var.enable_telemetry && zone.enable_telemetry
  }
  databricks_data_landing_zone_telemetry = {
    for key, zone in var.databricks_data_landing_zones : key => var.enable_telemetry && zone.enable_telemetry
  }
}
