terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.55.0"
    }
  }
}

locals {
  namespace_name = lower(replace("${var.env_prefix}-${var.namespace_name}", "_", "-"))
  eventhub_name  = lower(var.eventhub_name)
  tags = merge(
    { for key, value in {
      Environment = var.env_prefix
      ManagedBy   = "Terraform"
      Component   = "eventhub"
    } : key => value if !contains([for tag_key in keys(var.tags) : lower(tag_key)], lower(key)) },
    var.tags
  )
}

# Event Hub Namespace
resource "azurerm_eventhub_namespace" "eventhub" {
  name                          = local.namespace_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.sku_name
  capacity                      = var.capacity
  public_network_access_enabled = false
  local_authentication_enabled  = false
  minimum_tls_version           = "1.2"

  tags = local.tags
}

# Event Hub
resource "azurerm_eventhub" "events" {
  name              = local.eventhub_name
  namespace_id      = azurerm_eventhub_namespace.eventhub.id
  partition_count   = var.partition_count
  message_retention = var.message_retention
}

# Private endpoint for Event Hub (uses non-delegated privateendpoint-subnet)
resource "azurerm_private_endpoint" "eventhub" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "${local.namespace_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = lookup(var.subnet_ids, "privateendpoint-subnet", null)
  tags                = local.tags

  lifecycle {
    precondition {
      condition = can(regex(
        "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$",
        lookup(var.subnet_ids, "privateendpoint-subnet", "")
      ))
      error_message = "An explicit valid privateendpoint-subnet ID is required; node/delegated subnet fallback is not allowed."
    }
    precondition {
      condition     = var.private_dns_zone_id != null
      error_message = "An externally owned privatelink.servicebus.windows.net zone ID is required when the private endpoint is enabled."
    }
  }

  private_service_connection {
    name                           = "${local.namespace_name}-psc"
    private_connection_resource_id = azurerm_eventhub_namespace.eventhub.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "servicebus"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "sender" {
  for_each             = var.workload_principal_ids
  scope                = azurerm_eventhub.events.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "receiver" {
  for_each             = var.workload_principal_ids
  scope                = azurerm_eventhub.events.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = each.value
}