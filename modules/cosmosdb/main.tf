terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

resource "random_pet" "cosmos" {
  length = 1
  prefix = var.env_prefix
}

locals {
  cosmos_account_name       = lower(replace("${var.env_prefix}-${var.account_name}", "_", "-"))
  privateendpoint_subnet_id = lookup(var.subnet_ids, "privateendpoint-subnet", null)
  vnet_id                   = try(regex("(?i)^(.+)/subnets/[^/]+$", local.privateendpoint_subnet_id)[0], null)
  tags = merge(
    { for key, value in {
      Environment = var.env_prefix
      ManagedBy   = "Terraform"
      Component   = "cosmosdb"
    } : key => value if !contains([for tag_key in keys(var.tags) : lower(tag_key)], lower(key)) },
    var.tags
  )
}

# Private DNS zone for Cosmos DB
resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

# Virtual network link between VNET and private DNS zone
resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "${random_pet.cosmos.id}-cosmos-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

# Cosmos DB Account
resource "azurerm_cosmosdb_account" "cosmos" {
  count = var.create_account ? 1 : 0

  name                = local.cosmos_account_name
  location            = coalesce(var.account_location, var.location)
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  public_network_access_enabled         = var.public_network_access_enabled
  local_authentication_disabled         = true
  access_key_metadata_writes_enabled    = false
  network_acl_bypass_for_azure_services = false
  minimal_tls_version                   = "Tls12"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = coalesce(var.account_location, var.location)
    failover_priority = 0
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Cosmos DB Database
resource "azurerm_cosmosdb_sql_database" "appdb" {
  count = var.create_account ? 1 : 0

  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos[0].name

  lifecycle {
    prevent_destroy = true
  }
}

# Cosmos DB Container
resource "azurerm_cosmosdb_sql_container" "items" {
  count = var.create_account ? 1 : 0

  name                = var.container_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos[0].name
  database_name       = azurerm_cosmosdb_sql_database.appdb[0].name
  partition_key_paths = ["/id"]
  throughput          = var.throughput

  lifecycle {
    prevent_destroy = true
  }
}

# Private endpoint for Cosmos DB (uses non-delegated privateendpoint-subnet)
resource "azurerm_private_endpoint" "cosmos" {
  count = var.create_account ? 1 : 0

  name                = "${local.cosmos_account_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = local.privateendpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "${local.cosmos_account_name}-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.cosmos[0].id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "cosmos"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos.id]
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "application" {
  for_each = var.create_account ? var.application_principals : {}

  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos[0].name
  principal_id        = each.value.principal_id
  role_definition_id  = "${azurerm_cosmosdb_account.cosmos[0].id}/sqlRoleDefinitions/${each.value.role == "reader" ? "00000000-0000-0000-0000-000000000001" : "00000000-0000-0000-0000-000000000002"}"
  scope               = "${azurerm_cosmosdb_account.cosmos[0].id}/dbs/${azurerm_cosmosdb_sql_database.appdb[0].name}/colls/${azurerm_cosmosdb_sql_container.items[0].name}"
}

moved {
  from = azurerm_cosmosdb_account.cosmos
  to   = azurerm_cosmosdb_account.cosmos[0]
}

moved {
  from = azurerm_cosmosdb_sql_database.appdb
  to   = azurerm_cosmosdb_sql_database.appdb[0]
}

moved {
  from = azurerm_cosmosdb_sql_container.items
  to   = azurerm_cosmosdb_sql_container.items[0]
}

moved {
  from = azurerm_private_endpoint.cosmos
  to   = azurerm_private_endpoint.cosmos[0]
}