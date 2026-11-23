mock_provider "azurerm" {}

variables {
  name                = "fixturestorage001"
  resource_group_name = "rg-fixture"
  location            = "eastus"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/virtualNetworks/vnet-fixture/subnets/privateendpoint-subnet"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
}

run "private_blob_fixture" {
  command = plan
  assert {
    condition     = !azurerm_storage_account.this.public_network_access_enabled && !azurerm_storage_account.this.shared_access_key_enabled && !azurerm_storage_account.this.allow_nested_items_to_be_public
    error_message = "Blob fixtures must not expose public or shared-key access."
  }
  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].versioning_enabled && azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7 && output.container_name == "test-data"
    error_message = "The fixture must retain versions and soft-deleted blobs in the private test-data container."
  }
  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids == tolist([var.private_dns_zone_id]) && azurerm_private_endpoint.this.private_service_connection[0].subresource_names == tolist(["blob"])
    error_message = "Only Blob private connectivity may be configured with the externally owned Blob DNS zone."
  }
}

run "reject_missing_private_subnet" {
  command = plan
  variables {
    subnet_id = ""
  }
  expect_failures = [var.subnet_id]
}

run "reject_wrong_service_zone" {
  command = plan
  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-fixture/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net"
  }
  expect_failures = [var.private_dns_zone_id]
}

run "reject_unrecognized_replication" {
  command = plan
  variables {
    replication_type = "ANY"
  }
  expect_failures = [var.replication_type]
}
