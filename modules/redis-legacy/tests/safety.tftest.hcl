mock_provider "azapi" {}
mock_provider "azurerm" {}

run "disabled_has_no_resources_or_reads" {
  command = plan
  assert {
    condition = (
      length(azurerm_redis_cache.fixture) == 0 &&
      length(azurerm_private_endpoint.fixture) == 0 &&
      length(azurerm_redis_cache_access_policy_assignment.fixture) == 0 &&
      length(data.azurerm_resource_group.existing) == 0 &&
      length(data.azapi_resource.existing) == 0 &&
      output.redis_id == null && output.redis_hostname == null
    )
    error_message = "Unselected legacy paths must plan no resources/reads and return null."
  }
}

run "existing_reference_returns_real_outputs" {
  command = plan
  variables {
    existing_name                = "example-legacy"
    existing_resource_group_name = "example-rg"
  }
  override_data {
    target = data.azurerm_resource_group.existing[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
    }
  }
  override_data {
    target = data.azapi_resource.existing[0]
    values = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Cache/redis/example-legacy"
      name = "example-legacy"
      output = {
        properties = {
          hostName = "example-legacy.redis.cache.windows.net"
          sslPort  = 6380
        }
      }
    }
  }
  assert {
    condition = (
      length(azurerm_redis_cache.fixture) == 0 &&
      length(azurerm_private_endpoint.fixture) == 0 &&
      output.redis_id != null &&
      output.redis_name == "example-legacy" &&
      output.redis_hostname == "example-legacy.redis.cache.windows.net" &&
      output.redis_ssl_port == 6380
    )
    error_message = "Existing references must return cache metadata without creating or managing it."
  }
}

run "reject_old_tls" {
  command = plan
  variables {
    minimum_tls_version = "1.0"
  }
  expect_failures = [var.minimum_tls_version]
}

run "reject_plaintext_port" {
  command = plan
  variables {
    enable_non_ssl_port = true
  }
  expect_failures = [var.enable_non_ssl_port]
}

run "reject_partial_existing_reference" {
  command = plan
  variables {
    existing_name = "example-legacy"
  }
  expect_failures = [var.existing_name]
}

run "reject_unconfirmed_fixture_eligibility" {
  command = plan
  variables {
    enable_new          = true
    name                = "example-legacy"
    resource_group_name = "example-rg"
    location            = "eastus"
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/private-endpoints"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/privateDnsZones/privatelink.redis.cache.windows.net"
  }
  expect_failures = [azurerm_redis_cache.fixture[0]]
}

run "confirmed_fixture_is_private_and_keyless" {
  command = plan
  variables {
    enable_new            = true
    eligibility_confirmed = true
    name                  = "example-legacy"
    resource_group_name   = "example-rg"
    location              = "eastus"
    subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/private-endpoints"
    private_dns_zone_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/privateDnsZones/privatelink.redis.cache.windows.net"
  }
  assert {
    condition = (
      length(data.azapi_resource.existing) == 0 &&
      !azurerm_redis_cache.fixture[0].public_network_access_enabled &&
      !azurerm_redis_cache.fixture[0].access_keys_authentication_enabled &&
      !azurerm_redis_cache.fixture[0].non_ssl_port_enabled &&
      azurerm_redis_cache.fixture[0].redis_configuration[0].active_directory_authentication_enabled &&
      length(azurerm_private_endpoint.fixture) == 1
    )
    error_message = "Confirmed fixture must be private, Entra-only and distinct from the existing-reference path."
  }
}
