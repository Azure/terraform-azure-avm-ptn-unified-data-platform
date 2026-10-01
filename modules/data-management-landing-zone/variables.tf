variable "capacity_administration_members" {
  type        = set(string)
  description = "Fabric capacity administrators. Use a user principal name for an Entra user or an object ID for a service principal."
  nullable    = false

  validation {
    condition     = length(var.capacity_administration_members) > 0
    error_message = "At least one capacity administration member is required."
  }
}

variable "capacity_name" {
  type        = string
  description = "Name of the Azure Fabric capacity."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,62}$", var.capacity_name))
    error_message = "capacity_name must be 3-63 lowercase letters or numbers and start with a lowercase letter."
  }
}

variable "capacity_sku_name" {
  type        = string
  description = "Fabric capacity SKU, for example F2, F64, or F128. Select it from measured workload demand and feature requirements."
  nullable    = false

  validation {
    condition     = contains(["F2", "F4", "F8", "F16", "F32", "F64", "F128", "F256", "F512", "F1024", "F2048"], var.capacity_sku_name)
    error_message = "capacity_sku_name must be a supported Fabric F SKU."
  }
}

variable "location" {
  type        = string
  description = "Approved Azure region for the resource group and Fabric capacity. Region selection controls OneLake residency."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create when resource_group_resource_id is null."
  nullable    = false
}

variable "capacity_role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = "ARM role assignments to create on the Fabric capacity."
  nullable    = false

  validation {
    condition = alltrue([
      for assignment in values(var.capacity_role_assignments) :
      assignment.delegated_managed_identity_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.ManagedIdentity/userAssignedIdentities", assignment.delegated_managed_identity_resource_id))
    ])
    error_message = "Each capacity role assignment delegated_managed_identity_resource_id must be a valid user-assigned managed identity resource ID."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls whether anonymous module usage telemetry is enabled. No customer data or deployment values are collected."
  nullable    = false
}

variable "lock" {
  type = object({
    kind  = string
    name  = optional(string, null)
    notes = optional(string, null)
  })
  default     = null
  description = "Management lock applied to the Fabric capacity. kind must be CanNotDelete or ReadOnly."

  validation {
    # try() keeps this null guard independent of whether Terraform short-circuits `||`,
    # which it only does from 1.12 onwards. The module already requires 1.12, but the
    # guard stays version-independent by design.
    condition     = var.lock == null || try(contains(["CanNotDelete", "ReadOnly"], var.lock.kind), false)
    error_message = "lock.kind must be CanNotDelete or ReadOnly."
  }
}

variable "resource_group_resource_id" {
  type        = string
  default     = null
  description = "Resource ID of an existing resource group. When null, this module creates resource_group_name."

  validation {
    condition     = var.resource_group_resource_id == null || can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.resource_group_resource_id))
    error_message = "resource_group_resource_id must be a valid resource-group resource ID or null."
  }
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "Azure tags applied to resources. Supply ownership, environment, cost center, data classification, and criticality tags."
}
