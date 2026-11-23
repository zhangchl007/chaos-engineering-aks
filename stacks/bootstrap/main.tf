terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "4.55.0" }
    azapi   = { source = "Azure/azapi", version = "2.14.0" }
  }
  # Bootstrap cannot depend on the account it creates.
  backend "local" { path = "bootstrap.tfstate" }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}
provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

variable "subscription_id" {
  type        = string
  description = "Explicit bootstrap subscription."
}
variable "tenant_id" {
  type        = string
  description = "Explicit bootstrap tenant."
}
variable "location" {
  type        = string
  description = "Verified backend region."
}
variable "resource_group_name" {
  type        = string
  description = "Independent backend resource group."
}
variable "storage_account_name" {
  type        = string
  description = "Globally unique lowercase backend storage account name."
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Use a valid unique Azure storage name."
  }
}
variable "state_principal_ids" {
  type        = map(string)
  description = "Explicit identities needing backend Blob data access; object IDs, not client IDs."
  default     = {}
}

locals {
  tags = { environment = "test", managed_by = "terraform", project = "chaos-workshop", "chaos-excluded" = "true" }
}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
  lifecycle { prevent_destroy = true }
}
resource "azurerm_virtual_network" "state" {
  name                = "state-network"
  location            = var.location
  resource_group_name = azurerm_resource_group.state.name
  address_space       = ["10.50.0.0/16"]
  tags                = local.tags
}
resource "azurerm_subnet" "endpoint" {
  name                 = "state-endpoint"
  resource_group_name  = azurerm_resource_group.state.name
  virtual_network_name = azurerm_virtual_network.state.name
  address_prefixes     = ["10.50.0.0/24"]
}
resource "azurerm_storage_account" "state" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  tags                            = local.tags
  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }
  lifecycle { prevent_destroy = true }
}
resource "azapi_resource" "container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = "tfstate"
  parent_id = "${azurerm_storage_account.state.id}/blobServices/default"
  body      = { properties = { publicAccess = "None" } }
  lifecycle { prevent_destroy = true }
}
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.state.name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "state"
  resource_group_name   = azurerm_resource_group.state.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.state.id
  registration_enabled  = false
}
resource "azurerm_private_endpoint" "state" {
  name                = "state-blob"
  resource_group_name = azurerm_resource_group.state.name
  location            = var.location
  subnet_id           = azurerm_subnet.endpoint.id
  tags                = local.tags
  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
resource "azurerm_role_assignment" "state" {
  for_each             = var.state_principal_ids
  scope                = azapi_resource.container.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
output "backend" {
  description = "Non-secret backend parameters; each stage/environment requires a distinct key."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azapi_resource.container.name
    use_azuread_auth     = true
  }
}
