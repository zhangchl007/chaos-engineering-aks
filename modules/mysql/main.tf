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

resource "random_pet" "mysql" {
  length = 1
  prefix = var.env_prefix
}

locals {
  mysql_server_name = lower(replace("${var.env_prefix}-${var.server_name}", "_", "-"))
  mysql_subnet_id   = lookup(var.subnet_ids, "mysql-subnet", null)
  vnet_id           = try(regex("(?i)^(.+)/subnets/[^/]+$", local.mysql_subnet_id)[0], null)
  tags = merge(
    { for key, value in {
      Environment = var.env_prefix
      ManagedBy   = "Terraform"
      Component   = "mysql-flexible-server"
    } : key => value if !contains([for tag_key in keys(var.tags) : lower(tag_key)], lower(key)) },
    var.tags
  )
}

# Private DNS zone for MySQL Flexible Server
resource "azurerm_private_dns_zone" "mysql" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

# Virtual network link
resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "${random_pet.mysql.id}-mysql-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

# MySQL Flexible Server (uses delegated mysql-subnet)
resource "azurerm_mysql_flexible_server" "mysql" {
  name                = local.mysql_server_name
  resource_group_name = var.resource_group_name
  location            = var.location
  # Preserve the legacy 8.0 input while using the provider's supported value.
  version                = var.mysql_version == "8.0" ? "8.0.21" : var.mysql_version
  administrator_login    = var.admin_user
  administrator_password = var.admin_password

  sku_name = var.sku_name
  zone     = var.zone

  storage {
    size_gb           = var.storage_size
    auto_grow_enabled = true
  }

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = false

  dynamic "high_availability" {
    for_each = var.availability_mode == "Disabled" ? [] : [var.availability_mode]
    content {
      mode = high_availability.value
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [tags["CreatedDate"]]
    precondition {
      condition     = var.availability_mode == "Disabled" || !startswith(var.sku_name, "B_")
      error_message = "MySQL high availability requires a GP_ or MO_ SKU, not Burstable."
    }
  }

  delegated_subnet_id   = local.mysql_subnet_id
  private_dns_zone_id   = azurerm_private_dns_zone.mysql.id
  public_network_access = var.public_network_access_enabled ? "Enabled" : "Disabled"
  depends_on            = [azurerm_private_dns_zone_virtual_network_link.mysql]

  tags = local.tags
}

# Default database for applications
resource "azurerm_mysql_flexible_database" "appdb" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}
