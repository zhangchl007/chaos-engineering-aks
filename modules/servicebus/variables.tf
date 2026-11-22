variable "name" {
  description = "Globally unique Service Bus namespace name supplied by the caller."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for module-owned Service Bus resources."
  type        = string
}

variable "location" {
  description = "Azure region with Premium Service Bus support."
  type        = string
}

variable "subnet_id" {
  description = "Externally owned, non-delegated private endpoint subnet ID; alternatively supply subnet_ids."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Alternative externally owned subnet map containing privateendpoint-subnet; no node subnet fallback."
  type        = map(string)
  default     = {}
}

variable "private_dns_zone_id" {
  description = "Externally owned privatelink.servicebus.windows.net zone ID shared with Event Hubs, with VNet links managed externally."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/privatelink\\.servicebus\\.windows\\.net$", var.private_dns_zone_id))
    error_message = "Supply the resource ID of the shared privatelink.servicebus.windows.net private DNS zone."
  }
}

variable "sku" {
  description = "Service Bus SKU. This private-only fixture requires Premium."
  type        = string
  default     = "Premium"
  validation {
    condition     = var.sku == "Premium"
    error_message = "Private endpoints require Premium Service Bus; Basic and Standard are not supported here."
  }
}

variable "capacity" {
  description = "Premium messaging units (1, 2, 4, 8 or 16)."
  type        = number
  default     = 1
  validation {
    condition     = contains([1, 2, 4, 8, 16], var.capacity)
    error_message = "Premium capacity must be 1, 2, 4, 8 or 16."
  }
}

variable "tags" {
  description = "Caller-owned tags applied to namespace and private endpoint."
  type        = map(string)
  default     = {}
}

variable "queues" {
  description = "Stable queue names mapped to settings; defaults to a bounded test-queue fixture."
  type = map(object({
    max_delivery_count  = optional(number, 10)
    lock_duration       = optional(string, "PT1M")
    default_message_ttl = optional(string, "P1D")
  }))
  default = {
    test-queue = {}
  }
  validation {
    condition     = alltrue([for name, queue in var.queues : length(trimspace(name)) > 0 && queue.max_delivery_count >= 1 && floor(queue.max_delivery_count) == queue.max_delivery_count])
    error_message = "Queue names must be nonempty and max_delivery_count must be a positive integer."
  }
}

variable "topics" {
  description = "Explicit optional topics keyed by entity name; no topic is created by default."
  type = map(object({
    default_message_ttl = optional(string, "P1D")
  }))
  default = {}
}

variable "subscriptions" {
  description = "Explicit optional subscriptions with a unique stable key, name and topic_key referencing topics."
  type = map(object({
    name               = string
    topic_key          = string
    max_delivery_count = optional(number, 10)
  }))
  default = {}
  validation {
    condition     = alltrue([for subscription in values(var.subscriptions) : length(trimspace(subscription.name)) > 0 && subscription.max_delivery_count >= 1 && floor(subscription.max_delivery_count) == subscription.max_delivery_count])
    error_message = "Subscription names must be nonempty and max_delivery_count must be a positive integer."
  }
}

variable "workload_principal_ids" {
  description = "Optional stable-key map of Entra principal object IDs receiving entity-scoped data sender and receiver roles."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for id in values(var.workload_principal_ids) : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Workload principal IDs must be Entra object UUIDs."
  }
}
