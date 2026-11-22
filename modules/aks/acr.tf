data "azurerm_container_registry" "existing" {
  count               = var.use_existing_acr ? 1 : 0
  name                = var.existing_acr_name
  resource_group_name = var.existing_acr_resource_group
}

resource "azurerm_container_registry" "default" {
  count                         = var.use_existing_acr ? 0 : 1
  name                          = var.new_acr_name != "" ? var.new_acr_name : "${replace(random_pet.rg.id, "-", "")}acr"
  resource_group_name           = var.kube_resource_group_name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  count               = var.use_existing_acr ? 0 : 1
  name                = "privatelink.azurecr.io"
  resource_group_name = var.kube_resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.use_existing_acr ? 0 : 1
  name                  = "${var.env_prefix}-acr"
  resource_group_name   = var.kube_resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = regex("^(.+)/subnets/[^/]+$", var.subnet_ids["privateendpoint-subnet"])[0]
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "acr" {
  count               = var.use_existing_acr ? 0 : 1
  name                = "${var.env_prefix}-acr"
  resource_group_name = var.kube_resource_group_name
  location            = var.location
  subnet_id           = var.subnet_ids["privateendpoint-subnet"]
  tags                = var.tags
  private_service_connection {
    name                           = "registry"
    private_connection_resource_id = azurerm_container_registry.default[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "registry"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }
}

locals {
  acr_id           = var.use_existing_acr ? data.azurerm_container_registry.existing[0].id : azurerm_container_registry.default[0].id
  acr_login_server = var.use_existing_acr ? data.azurerm_container_registry.existing[0].login_server : azurerm_container_registry.default[0].login_server
}
