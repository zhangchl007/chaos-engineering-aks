mock_provider "azurerm" {}

variables {
  name                = "fixture-servicebus"
  resource_group_name = "rg-fixture"
  location            = "eastus"
  subnet_ids = {
    privateendpoint-subnet = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/virtualNetworks/vnet-fixture/subnets/privateendpoint-subnet"
  }
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net"
}

run "private_queue_fixture" {
  command = plan
  assert {
    condition     = output.queue_names == { test-queue = "test-queue" } && length(output.topic_names) == 0 && length(azurerm_servicebus_subscription.this) == 0
    error_message = "Default fixture must create only the requested test queue, not implicit topics or subscriptions."
  }
  assert {
    condition     = !azurerm_servicebus_namespace.this.public_network_access_enabled && !azurerm_servicebus_namespace.this.local_auth_enabled && azurerm_private_endpoint.this.subnet_id == var.subnet_ids["privateendpoint-subnet"]
    error_message = "Service Bus must remain private and use the explicit private endpoint subnet."
  }
}

run "reject_missing_private_subnet" {
  command = plan
  variables {
    subnet_ids = {}
  }
  expect_failures = [azurerm_private_endpoint.this]
}

run "reject_unknown_subscription_topic" {
  command = plan
  variables {
    subscriptions = {
      fixture = {
        name      = "test-subscription"
        topic_key = "undeclared"
      }
    }
  }
  expect_failures = [azurerm_servicebus_subscription.this["fixture"]]
}

run "reject_nonpremium_sku" {
  command = plan
  variables {
    sku = "Standard"
  }
  expect_failures = [var.sku]
}
