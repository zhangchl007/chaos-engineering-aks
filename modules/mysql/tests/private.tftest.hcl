mock_provider "azurerm" {}
mock_provider "random" {}

variables {
  resource_group_name = "fixture-rg"
  location            = "eastus"
  env_prefix          = "test"
  server_name         = "mysql-fixture"
  # Synthetic test input, never used against Azure.
  admin_password = "Mock-only-not-a-credential-123!"
  subnet_ids = {
    mysql-subnet = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/virtualNetworks/fixture-vnet/subnets/mysql"
  }
}

run "private_ha_server" {
  command = plan
  assert {
    condition     = azurerm_mysql_flexible_server.mysql.public_network_access == "Disabled" && azurerm_mysql_flexible_server.mysql.delegated_subnet_id == var.subnet_ids["mysql-subnet"]
    error_message = "MySQL must use only the explicitly provided delegated subnet without public access."
  }
  assert {
    condition     = azurerm_mysql_flexible_server.mysql.high_availability[0].mode == "ZoneRedundant" && azurerm_mysql_flexible_server.mysql.storage[0].auto_grow_enabled
    error_message = "HA must preserve the requested placement with storage auto-grow enabled."
  }
}

run "caller_tag_case_overrides_defaults" {
  command = plan
  variables {
    tags = {
      eNvIrOnMeNt = "dev"
      managedby   = "caller"
      component   = "caller-component"
      Owner       = "caller-team"
    }
  }
  assert {
    condition     = alltrue([for tags in [azurerm_private_dns_zone.mysql.tags, azurerm_private_dns_zone_virtual_network_link.mysql.tags, azurerm_mysql_flexible_server.mysql.tags] : tags == var.tags])
    error_message = "Caller tag casing must override module defaults without duplicate Azure tag keys on DNS or MySQL."
  }
}

run "reject_case_duplicate_tags" {
  command = plan
  variables {
    tags = { Environment = "dev", environment = "test" }
  }
  expect_failures = [var.tags]
}

run "disabled_ha_legacy_version" {
  command = plan
  variables {
    availability_mode = "Disabled"
    mysql_version     = "8.0"
  }
  assert {
    condition     = length(azurerm_mysql_flexible_server.mysql.high_availability) == 0 && azurerm_mysql_flexible_server.mysql.version == "8.0.21"
    error_message = "Disabled must omit the HA block, and legacy 8.0 must use the provider-supported version."
  }
}

run "reject_node_subnet_fallback" {
  command = plan
  variables {
    subnet_ids = {
      node-subnet = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/virtualNetworks/fixture-vnet/subnets/nodes"
    }
  }
  expect_failures = [var.subnet_ids]
}

run "reject_public_access" {
  command = plan
  variables {
    public_network_access_enabled = true
  }
  expect_failures = [var.public_network_access_enabled]
}

run "reject_unprefixed_sku" {
  command = plan
  variables {
    sku_name = "Standard_D2ds_v4"
  }
  expect_failures = [var.sku_name]
}
