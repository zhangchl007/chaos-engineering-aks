locals {
  subscription_id = var.subscription_id != null ? var.subscription_id : data.azapi_client_config.current[0].subscription_id
  tenant_id       = var.tenant_id != null ? var.tenant_id : data.azapi_client_config.current[0].tenant_id
}

provider "azurerm" {
  subscription_id                 = local.subscription_id
  tenant_id                       = local.tenant_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
