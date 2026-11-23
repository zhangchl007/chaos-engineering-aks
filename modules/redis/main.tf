terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.7.0, < 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.55.0, < 5.0"
    }
  }
}

locals {
  redis_enterprise_api_version = "2025-07-01"
  redis_name                   = lower(replace("${var.env_prefix}-${var.redis_name}", "_", "-"))
  eviction_policies = {
    allkeys-lru     = "AllKeysLRU"
    allkeys-lfu     = "AllKeysLFU"
    allkeys-random  = "AllKeysRandom"
    noeviction      = "NoEviction"
    volatile-lru    = "VolatileLRU"
    volatile-lfu    = "VolatileLFU"
    volatile-random = "VolatileRandom"
    volatile-ttl    = "VolatileTTL"
  }
  eviction_policy = lookup(local.eviction_policies, var.redis_eviction_policy, var.redis_eviction_policy)
}

data "azurerm_client_config" "current" {
  count = var.use_azapi ? 1 : 0
}

resource "azapi_resource" "cluster" {
  count     = var.use_azapi ? 1 : 0
  type      = "Microsoft.Cache/redisEnterprise@${local.redis_enterprise_api_version}"
  name      = local.redis_name
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current[0].subscription_id}/resourceGroups/${var.resource_group_name}"
  tags      = var.tags

  body = {
    sku = {
      name = var.redis_sku_name
    }
    properties = {
      minimumTlsVersion   = var.redis_minimum_tls_version
      highAvailability    = "Enabled"
      publicNetworkAccess = "Disabled"
    }
  }
  schema_validation_enabled = true

  lifecycle {
    precondition {
      condition     = length(local.redis_name) <= 60 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", local.redis_name))
      error_message = "The normalized environment-prefixed Redis name must be 1-60 alphanumeric/hyphen characters."
    }
    precondition {
      condition     = var.subnet_id != null && var.private_dns_zone_id != null
      error_message = "Enabled Managed Redis requires a private endpoint subnet_id and privatelink.redis.azure.net private_dns_zone_id."
    }
  }
}

resource "azapi_resource" "database" {
  count     = var.use_azapi ? 1 : 0
  type      = "Microsoft.Cache/redisEnterprise/databases@${local.redis_enterprise_api_version}"
  name      = var.database_name
  parent_id = azapi_resource.cluster[0].id

  body = {
    properties = {
      clientProtocol   = var.redis_client_protocol
      evictionPolicy   = local.eviction_policy
      clusteringPolicy = "OSSCluster"
      port             = 10000
      persistence = {
        aofEnabled = false
        rdbEnabled = false
      }
      modules = [
        for m in var.modules : {
          name = m
        }
      ]
      accessKeysAuthentication = "Disabled"
    }
  }
  schema_validation_enabled = true
}

resource "azapi_resource" "access_policy_assignment" {
  for_each  = var.use_azapi ? var.access_policy_assignments : {}
  type      = "Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@${local.redis_enterprise_api_version}"
  name      = each.key
  parent_id = azapi_resource.database[0].id
  body = {
    properties = {
      accessPolicyName = "default"
      user = {
        objectId = each.value
      }
    }
  }
  schema_validation_enabled = true
}

resource "azurerm_private_endpoint" "redis" {
  count               = var.use_azapi ? 1 : 0
  name                = "${local.redis_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${local.redis_name}-connection"
    private_connection_resource_id = azapi_resource.cluster[0].id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "redis"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

