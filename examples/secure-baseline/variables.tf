variable "capacity_administration_members" {
  type        = set(string)
  default     = null
  description = "Fabric capacity administrators as Entra user UPNs or service-principal object IDs. Defaults to the object ID of the deploying identity, which is the form Fabric expects for a service principal. Set this to your user principal name when deploying as a user."
}

variable "data_classification" {
  type        = string
  default     = "internal"
  description = "Organization-approved data classification tag value."
  nullable    = false
}

variable "domain_administration_group_object_id" {
  type        = string
  default     = null
  description = "Optional Entra group object ID granted the Fabric domain Admins role."
}

variable "enable_preview_features" {
  type        = bool
  default     = false
  description = "THIS IS A VARIABLE USED FOR A PREVIEW SERVICE/FEATURE, MICROSOFT MAY NOT PROVIDE SUPPORT FOR THIS, PLEASE CHECK THE PRODUCT DOCS FOR CLARIFICATION. Enables Fabric provider preview mode and the preview domain workspace assignment resource."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls whether anonymous usage telemetry is enabled for the deployed pattern module. Set to false to disable telemetry throughout the composition."
  nullable    = false
}

variable "enable_workspace_network_restrictions" {
  type        = bool
  default     = false
  description = "Whether to enable deny-by-default workspace outbound controls and the optional two-phase inbound lockdown."
  nullable    = false
}

variable "enable_workspace_private_link" {
  type        = bool
  default     = true
  description = "Whether to deploy workspace-level private link, including the example's virtual network, private endpoint subnet, and private DNS zone."
  nullable    = false
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment tag value."
  nullable    = false
}

variable "git_outbound_default_action" {
  type        = string
  default     = "Allow"
  description = "Default Fabric workspace Git outbound action. Use Deny only for workspaces where Git integration is prohibited."
  nullable    = false

  validation {
    condition     = contains(["Allow", "Deny"], var.git_outbound_default_action)
    error_message = "git_outbound_default_action must be Allow or Deny."
  }
}

variable "location" {
  type        = string
  default     = "swedencentral"
  description = "Azure region for the Fabric capacity and the example's networking resources."
  nullable    = false
}

variable "owner" {
  type        = string
  default     = "platform-team"
  description = "Accountable platform owner tag value."
  nullable    = false
}

variable "private_link_ready_for_lockdown" {
  type        = bool
  default     = false
  description = "Leave false for the first apply. Set true only after private endpoint approval and private DNS and access validation."
  nullable    = false
}

variable "subscription_id" {
  type        = string
  default     = null
  description = "Azure subscription to deploy into. Defaults to the subscription the AzAPI provider resolves from its environment (ARM_SUBSCRIPTION_ID or the Azure CLI default)."
}

variable "virtual_network_address_space" {
  type        = string
  default     = "10.100.0.0/24"
  description = "Address space of the example virtual network. The private endpoint subnet uses its first /27."
  nullable    = false
}

variable "workspace_administration_group_object_id" {
  type        = string
  default     = null
  description = "Optional Entra group object ID granted the Fabric workspace Admin role. The deploying identity is a workspace administrator as its creator."
}
