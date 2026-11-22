variable "resource_group_name" {
  description = "Resource group for Event Hub resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "env_prefix" {
  description = "Environment prefix used for naming"
  type        = string
}

variable "namespace_name" {
  description = "Base name for the Event Hubs namespace (env prefix will be prepended)"
  type        = string
  default     = "ehns"
}

variable "eventhub_name" {
  description = "Event Hub name"
  type        = string
  default     = "events"
}

variable "sku_name" {
  description = "Event Hubs namespace SKU"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.sku_name)
    error_message = "Private Event Hubs supports only Standard or Premium in this module."
  }
}

variable "capacity" {
  description = "Throughput Units / Capacity for the Event Hubs namespace"
  type        = number
  default     = 1
}

variable "message_retention" {
  description = "Message retention in days for the Event Hub"
  type        = number
  default     = 1
}

variable "partition_count" {
  description = "Number of partitions for the Event Hub"
  type        = number
  default     = 2
}

variable "enable_private_endpoint" {
  description = "Create a private endpoint using privateendpoint-subnet; disabling leaves public access disabled."
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "Externally owned subnet IDs; privateendpoint-subnet is required when the private endpoint is enabled."
  type        = map(string)
}

variable "private_dns_zone_id" {
  description = "Externally owned privatelink.servicebus.windows.net zone ID, shared with Service Bus and already linked to the workload VNet."
  type        = string
  default     = null
  validation {
    condition     = var.private_dns_zone_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/privatelink\\.servicebus\\.windows\\.net$", var.private_dns_zone_id))
    error_message = "Supply the resource ID of privatelink.servicebus.windows.net, not a zone name or another service's zone."
  }
}

variable "workload_principal_ids" {
  description = "Optional stable-key map of Entra principal object IDs receiving event-hub-scoped data sender and receiver roles."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for id in values(var.workload_principal_ids) : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Workload principal IDs must be Entra object UUIDs, not client IDs or resource IDs."
  }
}

variable "tags" {
  description = "Tags to apply to Event Hub resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = length(var.tags) == length(distinct([for key in keys(var.tags) : lower(key)]))
    error_message = "Azure tag names are case-insensitive; tags must not contain keys that differ only by case."
  }
}