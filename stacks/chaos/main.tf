terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "4.55.0" }
    azapi   = { source = "Azure/azapi", version = "2.14.0" }
  }
  backend "local" {
    path = "../../local-state/dev/chaos.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

variable "subscription_id" {
  type        = string
  description = "Explicit target subscription."
}
variable "tenant_id" {
  type        = string
  description = "Explicit target tenant."
}
variable "resource_group_id" {
  type        = string
  description = "Dedicated existing Workspace resource group ID."
}
variable "location" {
  type        = string
  description = "Supported Workspace deployment region; it need not match target regions."
  validation {
    condition = contains([
      "eastus2", "westus2", "westcentralus", "northeurope",
      "swedencentral", "uksouth", "japaneast"
    ], var.location)
    error_message = "Choose a supported Chaos Studio Workspace region, not the target region automatically."
  }
}
variable "name" {
  type        = string
  description = "Dedicated Workspace name."
}
variable "enabled" {
  type        = bool
  description = "Create configuration only, never execute faults."
  default     = false
}
variable "scopes" {
  type        = set(string)
  description = "Approved resource-group scopes."
  default     = []
}
variable "scenarios" {
  type = map(object({
    action_id        = string
    description      = string
    duration_minutes = optional(number, 1)
    target_ids       = set(string)
    parameters       = optional(map(string), {})
    locations        = optional(set(string), [])
    zones            = optional(set(string), [])
  }))
  description = "Approved bounded service-direct definitions."
  default     = {}
}
variable "permissions" {
  type = map(object({
    target_id    = string
    actions      = optional(set(string), [])
    data_actions = optional(set(string), [])
  }))
  description = "Verified target-specific permissions from cloud validation."
  default     = {}
}
variable "excluded_resource_ids" {
  type        = set(string)
  description = "Recovery and shared resource exclusions."
  default     = []
}
variable "allow_destructive_configuration" {
  type        = bool
  description = "Opt-in to defining destructive operations, not running them."
  default     = false
}

variable "linked_database_allowlist" {
  type        = set(string)
  description = "Additional explicitly approved affected linked databases for Managed Redis unlink."
  default     = []
}

variable "aks_extensions" {
  description = "Operator-owned extension references with explicit compatibility and installed namespace evidence."
  type = map(object({
    cluster_id             = string
    target_namespaces      = set(string)
    compatibility_verified = optional(bool, false)
    network_faults_enabled = optional(bool, false)
  }))
  default = {}
}

variable "pod_scenarios" {
  description = "Opt-in bounded pod definitions; installation and execution stay operator-owned."
  type = map(object({
    description              = string
    extension_key            = string
    namespace                = string
    labels                   = map(string)
    fault                    = optional(string, "pod_delete")
    app_kind                 = optional(string, "deployment")
    duration_seconds         = optional(number, 60)
    pods_affected_percentage = optional(number, 10)
    chaos_interval_seconds   = optional(number, 61)
    target_container         = optional(string)
    container_tools_verified = optional(bool, false)
    cpu_cores                = optional(number)
    memory_megabytes         = optional(number)
    latency_milliseconds     = optional(number)
    packet_loss_percentage   = optional(number)
  }))
  default = {}
}

module "chaos" {
  source                          = "../../modules/chaos"
  enabled                         = var.enabled
  name                            = var.name
  resource_group_id               = var.resource_group_id
  location                        = var.location
  scopes                          = var.scopes
  scenarios                       = var.scenarios
  permissions                     = var.permissions
  excluded_resource_ids           = var.excluded_resource_ids
  allow_destructive_configuration = var.allow_destructive_configuration
  linked_database_allowlist       = var.linked_database_allowlist
  aks_extensions                  = var.aks_extensions
  pod_scenarios                   = var.pod_scenarios
  tags                            = { environment = "test", managed_by = "terraform", project = "chaos-workshop" }
}

output "configuration_ids" {
  description = "IDs for separately authorized validation and execution."
  value       = module.chaos.configuration_ids
}

output "workspace_id" {
  description = "Workspace ID for onboarding and separately authorized Scenario configuration."
  value       = module.chaos.workspace_id
}

output "runtime_principal_id" {
  description = "Workspace runtime identity object ID for narrowly scoped permission review."
  value       = module.chaos.runtime_principal_id
}
