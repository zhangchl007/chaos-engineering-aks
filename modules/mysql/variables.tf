variable "resource_group_name" {
  description = "Resource group where MySQL Flexible Server will be deployed"
  type        = string
}

variable "location" {
  description = "Azure region for MySQL Flexible Server"
  type        = string
}

variable "env_prefix" {
  description = "Environment prefix used for naming"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs map from vnet module (must contain key 'mysql-subnet')"
  type        = map(string)
  validation {
    condition     = can(regex("(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", lookup(var.subnet_ids, "mysql-subnet", "")))
    error_message = "subnet_ids must contain mysql-subnet with an Azure subnet resource ID; node-subnet is not a fallback."
  }
}

variable "server_name" {
  description = "MySQL Flexible Server name (without env prefix)"
  type        = string
}

variable "admin_user" {
  description = "Administrator username for MySQL Flexible Server"
  type        = string
  default     = "mysqladmin"
}

variable "admin_password" {
  description = "Administrator password for MySQL Flexible Server"
  type        = string
  sensitive   = true
  nullable    = false
  validation {
    condition     = length(var.admin_password) >= 8 && length(var.admin_password) <= 128
    error_message = "The administrator password must be between 8 and 128 characters; Azure also enforces complexity."
  }
}

variable "sku_name" {
  description = "Tier-prefixed SKU for MySQL Flexible Server (e.g., GP_Standard_D2ds_v4)"
  type        = string
  default     = "GP_Standard_D2ds_v4"
  validation {
    condition     = can(regex("^(B|GP|MO)_Standard_[A-Za-z0-9_]+$", var.sku_name))
    error_message = "sku_name must start with B_, GP_, or MO_ followed by a Standard SKU."
  }
}

variable "storage_size" {
  description = "Storage size in GB"
  type        = number
  default     = 128
  validation {
    condition     = var.storage_size >= 20 && var.storage_size <= 16384 && floor(var.storage_size) == var.storage_size
    error_message = "storage_size must be an integer between 20 and 16384 GB."
  }
}

variable "backup_retention_days" {
  description = "Backup retention days (7-35)"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35 && floor(var.backup_retention_days) == var.backup_retention_days
    error_message = "backup_retention_days must be an integer between 7 and 35."
  }
}

variable "availability_mode" {
  description = "High availability mode: Disabled, ZoneRedundant, SameZone"
  type        = string
  default     = "ZoneRedundant"
  validation {
    condition     = contains(["Disabled", "SameZone", "ZoneRedundant"], var.availability_mode)
    error_message = "availability_mode must be Disabled, SameZone, or ZoneRedundant."
  }
}

variable "mysql_version" {
  description = "MySQL version"
  type        = string
  default     = "8.0.21"
  validation {
    condition     = contains(["5.7", "8.0", "8.0.21", "8.4"], var.mysql_version)
    error_message = "mysql_version must be 5.7, 8.0.21, or 8.4; legacy 8.0 is normalized to 8.0.21. Verify service lifecycle before deployment."
  }
}

variable "zone" {
  description = "Azure availability zone"
  type        = string
  default     = "1"
  validation {
    condition     = var.zone == null ? true : contains(["1", "2", "3"], var.zone)
    error_message = "zone must be 1, 2, 3, or null for Azure placement."
  }
}

variable "database_name" {
  description = "Default database name to create"
  type        = string
  default     = "appdb"
}

variable "tags" {
  description = "Tags to apply to MySQL resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = length(var.tags) == length(distinct([for key in keys(var.tags) : lower(key)]))
    error_message = "Azure tag names are case-insensitive; tags must not contain keys that differ only by case."
  }
}

variable "public_network_access_enabled" {
  description = "Private-only guardrail. Public network access cannot be enabled by this module."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.public_network_access_enabled
    error_message = "MySQL must remain private; public_network_access_enabled must be false."
  }
}