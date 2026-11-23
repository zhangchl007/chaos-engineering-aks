variable "resource_group_name" {
  description = "Resource group hosting the Managed Redis instance"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "redis_name" {
  description = "Azure Managed Redis name"
  type        = string
}

variable "redis_sku_name" {
  description = "Managed Redis SKU; regional availability must be verified (e.g. Balanced_B0)"
  type        = string
  default     = "Balanced_B0"
}

variable "redis_client_protocol" {
  description = "TLS-encrypted client protocol; plaintext is prohibited"
  type        = string
  default     = "Encrypted"
  validation {
    condition     = var.redis_client_protocol == "Encrypted"
    error_message = "Only Encrypted client connections are allowed."
  }
}

variable "redis_minimum_tls_version" {
  description = "Minimum TLS version"
  type        = string
  default     = "1.2"
  validation {
    condition     = var.redis_minimum_tls_version == "1.2"
    error_message = "The verified API and security baseline require TLS 1.2."
  }
}

variable "redis_enable_non_ssl_port" {
  description = "Enable plaintext port 6379"
  type        = bool
  default     = false
  validation {
    condition     = !var.redis_enable_non_ssl_port
    error_message = "Plaintext ports are prohibited."
  }
}

variable "redis_eviction_policy" {
  description = "Redis eviction policy (maxmemory-policy)"
  type        = string
  default     = "allkeys-lru"
  validation {
    condition = contains([
      "allkeys-lru", "allkeys-lfu", "allkeys-random", "noeviction",
      "volatile-lru", "volatile-lfu", "volatile-random", "volatile-ttl",
      "AllKeysLRU", "AllKeysLFU", "AllKeysRandom", "NoEviction",
      "VolatileLRU", "VolatileLFU", "VolatileRandom", "VolatileTTL"
    ], var.redis_eviction_policy)
    error_message = "Use a supported Redis eviction policy or its ARM enum spelling."
  }
}

variable "tags" {
  description = "Tags applied to Managed Redis"
  type        = map(string)
  default     = {}
}
variable "database_name" {
  description = "Name of the Redis database"
  type        = string
  default     = "default"
  validation {
    condition     = var.database_name == "default"
    error_message = "Managed Redis uses the default database."
  }
}
variable "modules" {
  description = "List of Redis modules to enable"
  type        = list(string)
  default     = ["RedisBloom", "RedisTimeSeries"]
}

variable "use_azapi" {
  description = "Create Managed Redis configuration; false disables all resources and reads (not runtime authorization)"
  type        = bool
  default     = true
}

variable "subnet_id" {
  description = "Caller-owned private endpoint subnet resource ID; required when use_azapi is true"
  type        = string
  default     = null
  validation {
    condition     = var.subnet_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be an Azure subnet resource ID."
  }
}

variable "private_dns_zone_id" {
  description = "Caller-owned privatelink.redis.azure.net private DNS zone ID; caller owns VNet links"
  type        = string
  default     = null
  validation {
    condition     = var.private_dns_zone_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/privatelink\\.redis\\.azure\\.net$", var.private_dns_zone_id))
    error_message = "Managed Redis requires the privatelink.redis.azure.net private DNS zone ID."
  }
}

variable "access_policy_assignments" {
  description = "Stable alphanumeric assignment names mapped to workload service principal object IDs; empty means no SDK identity is authorized"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for name, object_id in var.access_policy_assignments :
      can(regex("^[A-Za-z0-9]{1,60}$", name)) &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", object_id))
    ])
    error_message = "Assignment names must be 1-60 alphanumeric characters and values must be principal object ID UUIDs (not client IDs)."
  }
}
variable "env_prefix" {
  description = "Environment prefix used for naming"
  type        = string
}