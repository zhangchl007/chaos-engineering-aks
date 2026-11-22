data "azapi_client_config" "current" {
  count = var.subscription_id == null || var.tenant_id == null ? 1 : 0
}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}
