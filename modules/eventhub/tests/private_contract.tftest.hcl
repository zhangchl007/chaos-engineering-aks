mock_provider "azurerm" {}

variables {
  resource_group_name = "rg-fixture"
  location            = "eastus"
  env_prefix          = "fixture"
  subnet_ids = {
    privateendpoint-subnet = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/virtualNetworks/vnet-fixture/subnets/privateendpoint-subnet"
  }
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net"
}

run "disabled_endpoint_has_null_output" {
  command = plan
  variables {
    enable_private_endpoint = false
    subnet_ids              = {}
    private_dns_zone_id     = null
  }
  assert {
    condition     = output.private_endpoint_id == null && length(azurerm_private_endpoint.eventhub) == 0
    error_message = "Disabling the endpoint must not index a missing resource or require private inputs."
  }
  assert {
    condition     = !azurerm_eventhub_namespace.eventhub.public_network_access_enabled && !azurerm_eventhub_namespace.eventhub.local_authentication_enabled
    error_message = "Disabling the endpoint must not enable public networking or SAS."
  }
}

run "enabled_endpoint_uses_external_dns" {
  command = plan
  variables {
    tags = { environment = "dev", managedby = "caller", component = "caller-component" }
  }
  assert {
    condition     = azurerm_eventhub_namespace.eventhub.tags == var.tags && azurerm_private_endpoint.eventhub[0].tags == var.tags
    error_message = "Namespace and endpoint tag defaults must not duplicate case variants supplied by the caller."
  }
  assert {
    condition     = length(azurerm_private_endpoint.eventhub) == 1 && azurerm_private_endpoint.eventhub[0].private_dns_zone_group[0].private_dns_zone_ids == tolist([var.private_dns_zone_id])
    error_message = "The endpoint must associate the caller-owned shared DNS zone."
  }
}

run "no_node_subnet_fallback" {
  command = plan
  variables {
    subnet_ids = {
      node-subnet = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/virtualNetworks/vnet-fixture/subnets/node-subnet"
    }
  }
  expect_failures = [azurerm_private_endpoint.eventhub[0]]
}

run "reject_wrong_service_zone" {
  command = plan
  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }
  expect_failures = [var.private_dns_zone_id]
}
