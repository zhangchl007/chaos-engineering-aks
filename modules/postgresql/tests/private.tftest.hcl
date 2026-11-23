mock_provider "azurerm" {}

variables {
  name                = "postgresql-fixture"
  resource_group_name = "fixture-rg"
  location            = "eastus"
  delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/virtualNetworks/fixture-vnet/subnets/postgresql"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/privateDnsZones/fixture.postgres.database.azure.com"
  administrator_login = "pgfixture"
  # Synthetic test input, never used against Azure.
  administrator_password = "Mock-only-not-a-credential-123!"
}

run "private_ha_database" {
  command = plan
  assert {
    condition     = !azurerm_postgresql_flexible_server.postgresql.public_network_access_enabled && azurerm_postgresql_flexible_server.postgresql.delegated_subnet_id == var.delegated_subnet_id && azurerm_postgresql_flexible_server.postgresql.private_dns_zone_id == var.private_dns_zone_id
    error_message = "PostgreSQL must use the caller's private subnet and DNS zone without public access."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server.postgresql.high_availability[0].mode == "SameZone" && azurerm_postgresql_flexible_server.postgresql.version == var.postgresql_version && azurerm_postgresql_flexible_server_database.appdb.name == "appdb"
    error_message = "The default private PostgreSQL server must have SameZone HA and an application database."
  }
}

run "reject_invalid_subnet" {
  command = plan
  variables {
    delegated_subnet_id = "not-an-azure-subnet"
  }
  expect_failures = [var.delegated_subnet_id]
}

run "reject_public_access" {
  command = plan
  variables {
    public_network_access_enabled = true
  }
  expect_failures = [var.public_network_access_enabled]
}

run "reject_disabled_ha" {
  command = plan
  variables {
    ha_mode = "Disabled"
  }
  expect_failures = [var.ha_mode]
}
