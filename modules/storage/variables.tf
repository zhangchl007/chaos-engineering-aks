variable "name" {
  description = "Globally unique Azure-safe storage account name supplied by the caller."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account name must be 3-24 lowercase letters or digits; uniqueness is the caller's responsibility."
  }
}

variable "resource_group_name" {
  description = "Resource group for module-owned Blob fixture resources."
  type        = string
}

variable "location" {
  description = "Azure region supporting the selected replication type."
  type        = string
}

variable "subnet_id" {
  description = "Externally owned, non-delegated private endpoint subnet resource ID."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "Supply a complete private endpoint subnet resource ID."
  }
}

variable "private_dns_zone_id" {
  description = "Externally owned privatelink.blob.core.windows.net zone ID with workload VNet links managed externally."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$", var.private_dns_zone_id))
    error_message = "Supply the resource ID of privatelink.blob.core.windows.net."
  }
}

variable "tags" {
  description = "Caller-owned tags applied to storage account and private endpoint."
  type        = map(string)
  default     = {}
}

variable "replication_type" {
  description = "Standard StorageV2 replication; default ZRS is in-region redundancy, not cross-region DR."
  type        = string
  default     = "ZRS"
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Replication must be LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS; verify regional support before deployment."
  }
}

variable "soft_delete_retention_days" {
  description = "Blob and container soft-delete retention in days; does not run recovery operations."
  type        = number
  default     = 7
  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365 && floor(var.soft_delete_retention_days) == var.soft_delete_retention_days
    error_message = "Soft-delete retention must be an integer from 1 to 365 days."
  }
}

variable "workload_principal_ids" {
  description = "Optional stable-key map of Entra object IDs granted Blob data contributor on test-data only."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for id in values(var.workload_principal_ids) : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Workload principal IDs must be Entra object UUIDs."
  }
}
