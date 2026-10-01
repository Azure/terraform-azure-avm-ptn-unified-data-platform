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

variable "diagnostic_log_categories" {
  type        = set(string)
  default     = ["accounts", "clusters", "dbfs", "jobs"]
  description = "Azure Databricks diagnostic log categories. The defaults are supported categories that Azure Monitor exports at no cost."
  nullable    = false
}

variable "diagnostic_metric_categories" {
  type        = set(string)
  default     = []
  description = "Azure Databricks diagnostic metric categories selected by the deployment owner."
  nullable    = false
}

variable "diagnostic_setting_name" {
  type        = string
  default     = "platform-monitoring"
  description = "Name of the Azure Monitor diagnostic setting."
  nullable    = false
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Controls whether anonymous usage telemetry is enabled for the deployed pattern module. Set to false to disable telemetry throughout the composition."
  nullable    = false
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment tag value."
  nullable    = false
}

variable "location" {
  type        = string
  default     = "swedencentral"
  description = "Azure region for the Fabric capacity, the Databricks landing zone, and the example's supporting resources."
  nullable    = false
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Optional resource ID of an existing central Log Analytics workspace. When null, the example creates one."
}

variable "onelake_endpoint_host" {
  type        = string
  default     = "onelake.dfs.fabric.microsoft.com"
  description = "OneLake DFS host selected for global, regional, or workspace-private routing, without a URL scheme."
  nullable    = false
}

variable "onelake_path" {
  type        = string
  default     = "Tables"
  description = "Relative path within the example Lakehouse, for example Tables or Files/curated."
  nullable    = false
}

variable "owner" {
  type        = string
  default     = "platform-team"
  description = "Accountable platform owner tag value."
  nullable    = false
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether the Databricks UI/API public endpoint remains enabled. Disable only after Private Link is complete and verified."
  nullable    = false
}

variable "subscription_id" {
  type        = string
  default     = null
  description = "Azure subscription to deploy into. Defaults to the subscription the AzAPI provider resolves from its environment (ARM_SUBSCRIPTION_ID or the Azure CLI default)."
}

variable "virtual_network_address_space" {
  type        = string
  default     = "10.110.0.0/22"
  description = "Address space of the example virtual network. The two delegated Databricks subnets each use one /24 of it."
  nullable    = false
}
