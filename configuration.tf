variable "subscription_id" {
  type        = string
  description = "Optional Azure subscription override; defaults to the authenticated Azure context."
  default     = null
  validation {
    condition     = var.subscription_id == null || can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "Supply the intended subscription UUID."
  }
}

variable "tenant_id" {
  type        = string
  description = "Optional Microsoft Entra tenant override; defaults to the authenticated Azure context."
  default     = null
  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "Supply the intended tenant UUID."
  }
}

variable "environment" {
  type        = string
  description = "Non-production environment boundary."
  default     = "dev"
  validation {
    condition     = contains(["dev", "test"], var.environment)
    error_message = "This fixture root only supports dev and test."
  }
}

variable "tags" {
  type        = map(string)
  description = "Non-sensitive ownership and cost metadata."
  default = {
    project     = "chaos-workshop"
    owner       = "example-team"
    cost_center = "example-cost-center"
  }
  validation {
    condition     = length(var.tags) == length(distinct([for key in keys(var.tags) : lower(key)]))
    error_message = "Azure tag names are case-insensitive; tags must not contain keys that differ only by case."
  }
}

variable "components" {
  description = "Opt-in fixture creation; this never authorizes fault execution."
  type = object({
    mysql       = optional(bool, false)
    postgresql  = optional(bool, false)
    cosmosdb    = optional(bool, false)
    redis       = optional(bool, false)
    azure_cache = optional(bool, false)
    eventhub    = optional(bool, false)
    servicebus  = optional(bool, false)
    storage     = optional(bool, false)
    vm          = optional(bool, false)
    agfc        = optional(bool, false)
  })
  default = {}
}

variable "azure_cache_eligibility_confirmed" {
  description = "Confirmed current tenant eligibility for new Azure Cache for Redis; never inferred from Managed Redis or used to bypass Azure policy."
  type        = bool
  default     = false
  nullable    = false
}

variable "azure_cache_name" {
  description = "Optional globally unique classic Azure Cache name; null generates a stable random suffix for the new fixture."
  type        = string
  default     = null
}

variable "jumpserver_ssh_source_cidrs" {
  description = "Approved SSH management CIDRs for the public jumpserver; empty keeps its dedicated access NSG deny-only. Supply real addresses privately."
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for source in var.jumpserver_ssh_source_cidrs :
      can(cidrnetmask(source)) && try(tonumber(split("/", source)[1]) >= 24, false)
    ])
    error_message = "Use approved IPv4 management CIDRs of /24 or narrower, preferably /32; wildcard and all-Internet sources are prohibited."
  }
}

variable "retain_cosmos_network" {
  description = "Retain Cosmos private DNS/link and naming resources when account provisioning is disabled; false creates no Cosmos module unless components.cosmosdb is enabled."
  type        = bool
  default     = false
  nullable    = false
}

variable "kubernetes_version" {
  type        = string
  description = "Explicit supported Kubernetes patch version; verify regional availability before deployment."
  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Pin an explicit Kubernetes patch version; no automatic latest lookup."
  }
}

variable "node_zones" {
  type        = list(string)
  description = "Explicit availability zones for the dedicated test node pools."
  default     = ["1", "2", "3"]
  validation {
    condition     = length(var.node_zones) > 0 && alltrue([for z in var.node_zones : contains(["1", "2", "3"], z)])
    error_message = "Select explicit supported zones."
  }
}

variable "cluster_admin_group_object_ids" {
  type        = list(string)
  description = "Approved Entra group object IDs for cluster administration."
  default     = []
}

variable "postgresql_admin_password" {
  type        = string
  description = "Optional PostgreSQL admin password override; null or empty generates a strong password for an enabled fixture, stored in protected state."
  sensitive   = true
  default     = null
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique lowercase application storage name when enabled."
  default     = null
}

variable "enable_monitoring" {
  type        = bool
  description = "Provision bounded Log Analytics and AKS container monitoring."
  default     = true
}

variable "allow_public_agfc" {
  type        = bool
  description = "Explicit consent to the provider's public AGFC frontend; false blocks new creation rather than pretending private support."
  default     = false
}
