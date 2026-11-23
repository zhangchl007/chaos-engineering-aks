terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.55.0, < 5.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.7.0, < 3.0"
    }
  }
}

locals {
  reference_existing = !var.enable_new && var.existing_name != null && var.existing_resource_group_name != null
}

data "azurerm_resource_group" "existing" {
  count = local.reference_existing ? 1 : 0
  name  = var.existing_resource_group_name
}

# AzureRM's Redis data source retrieves keys. A GET-only AzAPI read avoids listKeys.
data "azapi_resource" "existing" {
  count     = local.reference_existing ? 1 : 0
  type      = "Microsoft.Cache/redis@2024-11-01"
  name      = var.existing_name
  parent_id = data.azurerm_resource_group.existing[0].id
  response_export_values = [
    "properties.hostName",
    "properties.sslPort"
  ]
}

resource "azurerm_redis_cache" "fixture" {
  count                              = var.enable_new ? 1 : 0
  name                               = var.name
  resource_group_name                = var.resource_group_name
  location                           = var.location
  sku_name                           = "Standard"
  family                             = "C"
  capacity                           = 1
  minimum_tls_version                = var.minimum_tls_version
  non_ssl_port_enabled               = var.enable_non_ssl_port
  public_network_access_enabled      = false
  access_keys_authentication_enabled = false
  redis_version                      = "6"
  tags                               = var.tags

  redis_configuration {
    authentication_enabled                  = true
    active_directory_authentication_enabled = true
  }

  lifecycle {
    precondition {
      condition     = var.eligibility_confirmed
      error_message = "New legacy fixtures require explicit confirmation of current tenant/cloud creation eligibility."
    }
    precondition {
      condition = (
        var.name != null && var.resource_group_name != null && var.location != null &&
        var.subnet_id != null && var.private_dns_zone_id != null
      )
      error_message = "New fixtures require name, resource_group_name, location, subnet_id and private_dns_zone_id."
    }
  }
}

resource "azurerm_private_endpoint" "fixture" {
  count               = var.enable_new ? 1 : 0
  name                = "${var.name}-pe"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-connection"
    private_connection_resource_id = azurerm_redis_cache.fixture[0].id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "redis"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_redis_cache_access_policy_assignment" "fixture" {
  for_each           = var.enable_new ? var.access_policy_assignments : {}
  name               = each.key
  redis_cache_id     = azurerm_redis_cache.fixture[0].id
  access_policy_name = "Data Contributor"
  object_id          = each.value
  object_id_alias    = each.key
}
