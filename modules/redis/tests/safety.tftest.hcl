mock_provider "azapi" {}
mock_provider "azurerm" {}

variables {
  resource_group_name = "example-rg"
  location            = "eastus"
  redis_name          = "Example_Cache"
  env_prefix          = "dev"
  use_azapi           = false
}

run "disabled_has_no_resources_or_reads" {
  command = plan
  assert {
    condition = (
      length(azapi_resource.cluster) == 0 &&
      length(azapi_resource.database) == 0 &&
      length(azapi_resource.access_policy_assignment) == 0 &&
      length(azurerm_private_endpoint.redis) == 0 &&
      length(data.azurerm_client_config.current) == 0 &&
      output.redis_cluster_id == null &&
      output.redis_cluster_name == null &&
      output.redis_database_id == null &&
      output.redis_database_name == null &&
      output.redis_database_primary_key == null &&
      output.redis_database_secondary_key == null
    )
    error_message = "Disabled Managed Redis must plan no resources/reads and null compatibility outputs."
  }
}

run "reject_plaintext_protocol" {
  command = plan
  variables {
    redis_client_protocol = "Plaintext"
  }
  expect_failures = [var.redis_client_protocol]
}

run "reject_old_tls" {
  command = plan
  variables {
    redis_minimum_tls_version = "1.1"
  }
  expect_failures = [var.redis_minimum_tls_version]
}

run "reject_plaintext_port" {
  command = plan
  variables {
    redis_enable_non_ssl_port = true
  }
  expect_failures = [var.redis_enable_non_ssl_port]
}

run "enabled_is_private_keyless_and_normalized" {
  command = plan
  variables {
    use_azapi           = true
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/private-endpoints"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/privateDnsZones/privatelink.redis.azure.net"
    modules             = []
  }
  override_data {
    target = data.azurerm_client_config.current[0]
    values = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  override_resource {
    target = azapi_resource.cluster[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Cache/redisEnterprise/dev-example-cache"
    }
  }
  assert {
    condition = (
      azapi_resource.cluster[0].name == "dev-example-cache" &&
      azapi_resource.cluster[0].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg" &&
      azapi_resource.cluster[0].body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.cluster[0].schema_validation_enabled &&
      azapi_resource.database[0].body.properties.accessKeysAuthentication == "Disabled" &&
      azapi_resource.database[0].body.properties.evictionPolicy == "AllKeysLRU" &&
      azurerm_private_endpoint.redis[0].private_service_connection[0].subresource_names == tolist(["redisEnterprise"])
    )
    error_message = "Enabled Managed Redis must use normalized naming, verified ARM enums, private networking and disabled key authentication."
  }
}
