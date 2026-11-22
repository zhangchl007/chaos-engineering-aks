terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.55.0"
    }
  }
}

resource "azurerm_storage_account" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = var.replication_type
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  default_to_oauth_authentication = true
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }
}

# storage_account_id selects the ARM API, not shared-key container creation.
resource "azurerm_storage_container" "this" {
  name                  = "test-data"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "this" {
  name                = "${var.name}-blob-pe"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "blob_data" {
  for_each             = var.workload_principal_ids
  scope                = azurerm_storage_container.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
