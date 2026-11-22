terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

resource "azurerm_postgresql_flexible_server" "postgresql" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = var.public_network_access_enabled
  administrator_login           = var.administrator_login
  administrator_password        = var.administrator_password
  sku_name                      = var.sku_name
  version                       = var.postgresql_version
  storage_mb                    = var.storage_mb
  backup_retention_days         = var.backup_retention_days
  geo_redundant_backup_enabled  = false
  tags                          = merge({ managed_by = "Terraform", component = "postgresql" }, var.tags)

  high_availability {
    mode = var.ha_mode
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone,
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "appdb" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.postgresql.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}
