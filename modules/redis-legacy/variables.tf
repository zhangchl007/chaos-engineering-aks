variable "existing_name" {
  description = "Existing Microsoft.Cache/redis name; null disables the existing-reference path"
  type        = string
  default     = null
  validation {
    condition = (
      (var.existing_name == null) == (var.existing_resource_group_name == null) &&
      (!var.enable_new || (var.existing_name == null && var.existing_resource_group_name == null))
    )
    error_message = "Supply both existing_name and existing_resource_group_name, or neither; existing and new paths are mutually exclusive."
  }
}

variable "existing_resource_group_name" {
  description = "Resource group owning the existing legacy cache; never imported or modified"
  type        = string
  default     = null
}

variable "enable_new" {
  description = "Opt in to a dedicated legacy Standard C1 fixture; not fault execution authorization"
  type        = bool
  default     = false
}

variable "eligibility_confirmed" {
  description = "Operator confirms current tenant/cloud eligibility to create legacy caches; no bypass of Azure policy"
  type        = bool
  default     = false
}

variable "name" {
  description = "Globally unique new fixture name; required with enable_new"
  type        = string
  default     = null
  validation {
    condition     = var.name == null ? true : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$", var.name))
    error_message = "Use a 2-63 character alphanumeric/hyphen fixture name."
  }
}

variable "resource_group_name" {
  description = "Caller-owned resource group for the new fixture"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region of the new fixture and private endpoint"
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Caller-owned private endpoint subnet ID; not Redis VNet injection; required for new fixtures"
  type        = string
  default     = null
  validation {
    condition     = var.subnet_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be an Azure subnet resource ID."
  }
}

variable "private_dns_zone_id" {
  description = "Caller-owned privatelink.redis.cache.windows.net zone ID; required for new fixtures; caller owns VNet links"
  type        = string
  default     = null
  validation {
    condition     = var.private_dns_zone_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/privatelink\\.redis\\.cache\\.windows\\.net$", var.private_dns_zone_id))
    error_message = "Legacy Redis requires privatelink.redis.cache.windows.net, not Managed Redis DNS."
  }
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for new fixtures"
  type        = string
  default     = "1.2"
  validation {
    condition     = var.minimum_tls_version == "1.2"
    error_message = "TLS 1.2 is required."
  }
}

variable "enable_non_ssl_port" {
  description = "Compatibility control for plaintext; must remain false"
  type        = bool
  default     = false
  validation {
    condition     = !var.enable_non_ssl_port
    error_message = "Plaintext Redis ports are prohibited."
  }
}

variable "access_policy_assignments" {
  description = "Stable fixture assignment names mapped to workload principal object IDs; existing-cache permissions remain owner-managed"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for name, object_id in var.access_policy_assignments :
      can(regex("^[A-Za-z0-9]{1,60}$", name)) &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", object_id))
    ])
    error_message = "Use alphanumeric assignment names and principal object ID UUIDs, not client IDs."
  }
}

variable "tags" {
  description = "Tags for new fixture resources"
  type        = map(string)
  default     = {}
}
