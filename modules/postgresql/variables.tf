variable "name" {
  description = "Globally unique PostgreSQL Flexible Server name"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 lowercase alphanumeric or hyphen characters, with alphanumeric ends."
  }
}

variable "resource_group_name" {
  description = "Existing resource group owned by the caller"
  type        = string
}

variable "location" {
  description = "Azure region; verify SKU, version, and HA availability before deployment"
  type        = string
}

variable "delegated_subnet_id" {
  description = "Existing dedicated subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers"
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.delegated_subnet_id))
    error_message = "delegated_subnet_id must be an Azure subnet resource ID."
  }
}

variable "private_dns_zone_id" {
  description = "Existing private DNS zone ending .postgres.database.azure.com; caller must link it to the delegated subnet VNet before server creation"
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+\\.postgres\\.database\\.azure\\.com$", var.private_dns_zone_id))
    error_message = "private_dns_zone_id must identify an Azure private DNS zone ending .postgres.database.azure.com."
  }
}

variable "administrator_login" {
  description = "Administrator login for private PostgreSQL password authentication"
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.administrator_login)) && !contains(["admin", "administrator", "azure_superuser", "azure_pg_admin", "root", "guest", "public"], lower(var.administrator_login))
    error_message = "administrator_login must be a non-reserved PostgreSQL login, starting with a letter and at most 63 characters."
  }
}

variable "administrator_password" {
  description = "Administrator password supplied privately; sensitive values still enter state and plan"
  type        = string
  sensitive   = true
  nullable    = false
  validation {
    condition     = length(var.administrator_password) >= 8 && length(var.administrator_password) <= 128
    error_message = "The administrator password must be between 8 and 128 characters; Azure also enforces complexity."
  }
}

variable "sku_name" {
  description = "HA-capable General Purpose or Memory Optimized PostgreSQL SKU"
  type        = string
  default     = "GP_Standard_D2s_v3"
  validation {
    condition     = can(regex("^(GP|MO)_Standard_[A-Za-z0-9_]+$", var.sku_name))
    error_message = "sku_name must be a GP_ or MO_ Standard SKU because this module requires HA."
  }
}

variable "postgresql_version" {
  description = "PostgreSQL major version as a string; verify current service lifecycle"
  type        = string
  default     = "16"
  validation {
    condition     = contains(["11", "12", "13", "14", "15", "16", "17", "18"], var.postgresql_version)
    error_message = "postgresql_version must be a PostgreSQL major version supported by AzureRM 4.55.0 (11 through 18)."
  }
}

variable "storage_mb" {
  description = "Storage size in MB supported by AzureRM 4.55.0; shrinking can force replacement"
  type        = number
  default     = 32768
  validation {
    condition     = contains([32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4193280, 4194304, 8388608, 16777216, 33553408], var.storage_mb)
    error_message = "storage_mb must be a supported PostgreSQL Flexible Server storage size."
  }
}

variable "ha_mode" {
  description = "HA placement: SameZone or ZoneRedundant; regional availability must be verified"
  type        = string
  default     = "SameZone"
  validation {
    condition     = contains(["SameZone", "ZoneRedundant"], var.ha_mode)
    error_message = "ha_mode must be SameZone or ZoneRedundant."
  }
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35 && floor(var.backup_retention_days) == var.backup_retention_days
    error_message = "backup_retention_days must be an integer between 7 and 35."
  }
}

variable "database_name" {
  description = "Application database created on the server"
  type        = string
  default     = "appdb"
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.database_name)) && !contains(["postgres", "template0", "template1", "azure_maintenance", "azure_sys"], var.database_name)
    error_message = "database_name must be a non-reserved lowercase PostgreSQL identifier of at most 63 characters."
  }
}

variable "tags" {
  description = "Tags supplied by the caller, including environment, project, owner, and cost_center"
  type        = map(string)
  default     = {}
}

variable "public_network_access_enabled" {
  description = "Private-only guardrail. Public network access cannot be enabled by this module."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.public_network_access_enabled
    error_message = "PostgreSQL must remain private; public_network_access_enabled must be false."
  }
}
