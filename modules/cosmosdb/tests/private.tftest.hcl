mock_provider "azurerm" {
  override_during = plan
  mock_resource "azurerm_cosmosdb_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.DocumentDB/databaseAccounts/test-cosmos"
    }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
    }
  }
}
mock_provider "random" {}

variables {
  resource_group_name = "fixture-rg"
  location            = "eastus"
  env_prefix          = "test"
  subnet_ids = {
    privateendpoint-subnet = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/virtualNetworks/fixture-vnet/subnets/private-endpoints"
  }
}

run "private_single_region" {
  command = plan
  assert {
    condition     = azurerm_cosmosdb_account.cosmos[0].location == var.location && one(azurerm_cosmosdb_account.cosmos[0].geo_location).location == var.location && azurerm_private_endpoint.cosmos[0].location == var.location
    error_message = "Omitting an account region override must retain the original account, primary and endpoint region."
  }
  assert {
    condition     = !azurerm_cosmosdb_account.cosmos[0].public_network_access_enabled && azurerm_cosmosdb_account.cosmos[0].local_authentication_disabled && !azurerm_cosmosdb_account.cosmos[0].network_acl_bypass_for_azure_services
    error_message = "Cosmos must have no public access, shared-key authentication, or Azure-service bypass."
  }
  assert {
    condition     = length(azurerm_private_endpoint.cosmos[0].private_dns_zone_group[0].private_dns_zone_ids) == 1 && azurerm_private_endpoint.cosmos[0].private_dns_zone_group[0].private_dns_zone_ids[0] == azurerm_private_dns_zone.cosmos.id && azurerm_private_endpoint.cosmos[0].subnet_id == var.subnet_ids["privateendpoint-subnet"] && azurerm_private_dns_zone_virtual_network_link.cosmos.virtual_network_id == trimsuffix(var.subnet_ids["privateendpoint-subnet"], "/subnets/private-endpoints")
    error_message = "The endpoint must have a DNS zone group and its zone must link to the endpoint VNet."
  }
  assert {
    condition     = length(azurerm_cosmosdb_account.cosmos[0].geo_location) == 1 && length(azurerm_cosmosdb_sql_role_assignment.application) == 0
    error_message = "No extra region or application permission should be created by default."
  }
}

run "account_region_override_and_caller_tags" {
  command = plan
  variables {
    account_location = "westus2"
    tags = {
      environment = "dev"
      managedby   = "caller"
      component   = "caller-component"
      Owner       = "caller-team"
    }
  }
  assert {
    condition     = azurerm_cosmosdb_account.cosmos[0].location == "westus2" && one(azurerm_cosmosdb_account.cosmos[0].geo_location).location == "westus2" && azurerm_private_endpoint.cosmos[0].location == var.location
    error_message = "Only the account and primary region may move; the endpoint must remain in the supplied VNet region."
  }
  assert {
    condition     = alltrue([for tags in [azurerm_private_dns_zone.cosmos.tags, azurerm_private_dns_zone_virtual_network_link.cosmos.tags, azurerm_cosmosdb_account.cosmos[0].tags, azurerm_private_endpoint.cosmos[0].tags] : tags == var.tags])
    error_message = "Caller tags must replace case-insensitive defaults on all Cosmos resources, preserving custom tag casing/values."
  }
}

run "reject_case_duplicate_tags" {
  command = plan
  variables {
    tags = { Environment = "dev", environment = "test" }
  }
  expect_failures = [var.tags]
}

run "reject_empty_account_region" {
  command = plan
  variables {
    account_location = ""
  }
  expect_failures = [var.account_location]
}

run "explicit_container_reader" {
  command = plan
  variables {
    application_principals = {
      fixture = {
        principal_id = "00000000-0000-0000-0000-000000000000"
        role         = "reader"
      }
    }
  }
  assert {
    condition     = azurerm_cosmosdb_sql_role_assignment.application["fixture"].scope == "${azurerm_cosmosdb_account.cosmos[0].id}/dbs/appdb/colls/items" && azurerm_cosmosdb_sql_role_assignment.application["fixture"].role_definition_id == "${azurerm_cosmosdb_account.cosmos[0].id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001"
    error_message = "An explicit reader must receive only the built-in data reader role at this container's scope."
  }

}

run "network_only_has_no_business_resources" {
  command = plan
  variables {
    create_account = false
    application_principals = {
      fixture = {
        principal_id = "00000000-0000-0000-0000-000000000000"
        role         = "reader"
      }
    }
  }
  assert {
    condition     = length(azurerm_cosmosdb_account.cosmos) == 0 && length(azurerm_cosmosdb_sql_database.appdb) == 0 && length(azurerm_cosmosdb_sql_container.items) == 0 && length(azurerm_private_endpoint.cosmos) == 0 && length(azurerm_cosmosdb_sql_role_assignment.application) == 0
    error_message = "Network-only mode must not create any Cosmos business resources or application roles."
  }
  assert {
    condition     = azurerm_private_dns_zone.cosmos.name == "privatelink.documents.azure.com" && azurerm_private_dns_zone_virtual_network_link.cosmos.virtual_network_id == trimsuffix(var.subnet_ids["privateendpoint-subnet"], "/subnets/private-endpoints") && random_pet.cosmos.prefix == var.env_prefix
    error_message = "Network-only mode must retain the original DNS zone/link and naming resource."
  }
  assert {
    condition     = output.cosmosdb_account_id == null && output.cosmosdb_account_name == null && output.cosmosdb_endpoint == null && output.database_name == null && output.container_name == null && output.private_endpoint_id == null
    error_message = "Disabled Cosmos business outputs must be null, never fake resource IDs or names."
  }
}

run "reject_malformed_subnet" {
  command = plan
  variables {
    subnet_ids = {
      privateendpoint-subnet = "not-an-azure-subnet"
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

run "reject_broad_role" {
  command = plan
  variables {
    application_principals = {
      fixture = {
        principal_id = "00000000-0000-0000-0000-000000000000"
        role         = "Owner"
      }
    }
  }
  expect_failures = [var.application_principals]
}
