terraform {
  required_version = ">= 1.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.55.0"
    }
  }
}

locals {
  subnet_id = var.subnet_id != null ? var.subnet_id : lookup(var.subnet_ids, "privateendpoint-subnet", null)
  entities = merge(
    { for key, queue in azurerm_servicebus_queue.this : "queue/${key}" => queue.id },
    { for key, topic in azurerm_servicebus_topic.this : "topic/${key}" => topic.id }
  )
  data_role_assignments = {
    for pair in setproduct(keys(local.entities), keys(var.workload_principal_ids)) :
    "${pair[0]}/${pair[1]}" => {
      scope        = local.entities[pair[0]]
      principal_id = var.workload_principal_ids[pair[1]]
    }
  }
}

resource "azurerm_servicebus_namespace" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  capacity                      = var.capacity
  premium_messaging_partitions  = 1
  public_network_access_enabled = false
  local_auth_enabled            = false
  minimum_tls_version           = "1.2"
  tags                          = var.tags
}

resource "azurerm_servicebus_queue" "this" {
  for_each                             = var.queues
  name                                 = each.key
  namespace_id                         = azurerm_servicebus_namespace.this.id
  max_delivery_count                   = each.value.max_delivery_count
  lock_duration                        = each.value.lock_duration
  default_message_ttl                  = each.value.default_message_ttl
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_topic" "this" {
  for_each            = var.topics
  name                = each.key
  namespace_id        = azurerm_servicebus_namespace.this.id
  default_message_ttl = each.value.default_message_ttl
}

resource "azurerm_servicebus_subscription" "this" {
  for_each                             = var.subscriptions
  name                                 = each.value.name
  topic_id                             = try(azurerm_servicebus_topic.this[each.value.topic_key].id, null)
  max_delivery_count                   = each.value.max_delivery_count
  dead_lettering_on_message_expiration = true

  lifecycle {
    precondition {
      condition     = contains(keys(var.topics), each.value.topic_key)
      error_message = "Each subscription must reference a topic_key declared in topics."
    }
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "${var.name}-pe"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = local.subnet_id
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", local.subnet_id))
      error_message = "Supply subnet_id or subnet_ids[\"privateendpoint-subnet\"] with a valid non-delegated subnet resource ID."
    }
    precondition {
      condition     = var.subnet_id == null || !contains(keys(var.subnet_ids), "privateendpoint-subnet") ? true : var.subnet_id == var.subnet_ids["privateendpoint-subnet"]
      error_message = "If both subnet contracts are supplied, they must identify the same private endpoint subnet."
    }
  }

  private_service_connection {
    name                           = "${var.name}-psc"
    private_connection_resource_id = azurerm_servicebus_namespace.this.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "servicebus"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "sender" {
  for_each             = local.data_role_assignments
  scope                = each.value.scope
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "receiver" {
  for_each             = local.data_role_assignments
  scope                = each.value.scope
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = each.value.principal_id
}
