variable "create_account" {
  description = "Create the account, database, container, endpoint and application roles; false retains only module-owned private DNS/link and naming resources."
  type        = bool
  default     = true
  nullable    = false
}

variable "resource_group_name" {
  description = "Resource group for Cosmos DB"
  type        = string
}

variable "location" {
  description = "Azure region of the supplied VNet/subnet and private endpoint; also the default account region"
  type        = string
}

variable "account_location" {
  description = "Optional Cosmos account and primary region override; null uses location. Verify regional capacity and approval before changing an existing account."
  type        = string
  default     = null
  validation {
    condition     = var.account_location == null || can(regex("^[a-z][a-z0-9]+$", var.account_location))
    error_message = "account_location must be null or a lowercase Azure region name without spaces."
  }
}

variable "env_prefix" {
  description = "Environment prefix for naming"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs map; privateendpoint-subnet must be a non-delegated private endpoint subnet"
  type        = map(string)
  validation {
    condition     = can(regex("(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", lookup(var.subnet_ids, "privateendpoint-subnet", "")))
    error_message = "subnet_ids must contain privateendpoint-subnet with an Azure subnet resource ID; node-subnet is not a fallback."
  }
}

variable "account_name" {
  description = "Cosmos DB account name (without env prefix)"
  type        = string
  default     = "cosmos"
}

variable "database_name" {
  description = "Cosmos DB database name"
  type        = string
  default     = "appdb"
}

variable "container_name" {
  description = "Cosmos DB container name"
  type        = string
  default     = "items"
}

variable "throughput" {
  description = "Cosmos DB manual throughput (RU/s)"
  type        = number
  default     = 400
  validation {
    condition     = var.throughput >= 400 && var.throughput % 100 == 0
    error_message = "throughput must be at least 400 RU/s and a multiple of 100."
  }
}

variable "tags" {
  description = "Tags to apply to Cosmos DB resources"
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
    error_message = "Cosmos DB must remain private; public_network_access_enabled must be false."
  }
}

variable "application_principals" {
  description = "Explicit Entra principal object IDs with reader or contributor data-plane access to this module's container only; no assignments by default"
  type = map(object({
    principal_id = string
    role         = string
  }))
  default = {}
  validation {
    condition = alltrue([
      for principal in values(var.application_principals) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", principal.principal_id)) &&
      contains(["reader", "contributor"], principal.role)
    ])
    error_message = "Each application principal requires an Entra object ID GUID and role reader or contributor."
  }
}