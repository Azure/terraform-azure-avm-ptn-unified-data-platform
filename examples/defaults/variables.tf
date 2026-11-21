variable "capacity_administration_members" {
  type        = set(string)
  default     = null
  description = "Fabric capacity administrators as Entra user UPNs or service-principal object IDs. Defaults to the object ID of the deploying identity, which is the form Fabric expects for a service principal. Set this to your user principal name when deploying as a user."
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls whether anonymous usage telemetry is enabled for the deployed pattern module. Set to false to disable telemetry throughout the composition."
  nullable    = false
}

variable "location" {
  type        = string
  default     = "swedencentral"
  description = "Azure region for the Fabric capacity and its resource group. Fabric capacity-unit quota is granted per subscription and region, and only some regions, such as swedencentral and francecentral, have it by default. The default, swedencentral, lets the example deploy without a quota increase request."
  nullable    = false
}

variable "subscription_id" {
  type        = string
  default     = null
  description = "Azure subscription to deploy into. Defaults to the subscription the AzAPI provider resolves from its environment (ARM_SUBSCRIPTION_ID or the Azure CLI default)."
}
