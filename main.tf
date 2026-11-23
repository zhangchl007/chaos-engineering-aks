locals {
  kube_resource_group_name = "${var.env_prefix}-${var.kube_resource_group_name}"
  cluster_name             = "${var.env_prefix}-${var.cluster_name}"
  kube_vnet_name           = "${var.env_prefix}-${var.kube_vnet_name}"
  tags = merge(
    { for key, value in var.tags : key => value if !contains(["environment", "managed_by"], lower(key)) },
    { environment = var.environment, managed_by = "terraform" }
  )
  dns_zones = {
    messaging = "privatelink.servicebus.windows.net"
    blob      = "privatelink.blob.core.windows.net"
    postgres  = "${var.env_prefix}.postgres.database.azure.com"
  }
}

resource "azurerm_resource_group" "kube" {
  name     = local.kube_resource_group_name
  location = var.location
  tags     = local.tags
}

module "kube_network" {
  source              = "./modules/vnet"
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  vnet_name           = local.kube_vnet_name
  address_space       = var.address_space
  subnets             = var.subnets
}

resource "azurerm_private_dns_zone" "service" {
  for_each            = local.dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.kube.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "service" {
  for_each              = local.dns_zones
  name                  = "${var.env_prefix}-${each.key}"
  resource_group_name   = azurerm_resource_group.kube.name
  private_dns_zone_name = azurerm_private_dns_zone.service[each.key].name
  virtual_network_id    = module.kube_network.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

module "aks" {
  source                         = "./modules/aks"
  kube_resource_group_name       = azurerm_resource_group.kube.name
  location                       = var.location
  cluster_name                   = local.cluster_name
  kubernetes_version             = var.kubernetes_version
  node_zones                     = var.node_zones
  cluster_admin_group_object_ids = var.cluster_admin_group_object_ids
  nodepool_nodes_count           = var.nodepool_nodes_count
  nodepool_vm_size               = var.nodepool_vm_size
  network_dns_service_ip         = var.network_dns_service_ip
  network_service_cidr           = var.network_service_cidr
  username                       = var.username
  ssh_public_key                 = var.ssh_public_key
  env_prefix                     = var.env_prefix
  kube_version_prefix            = var.kube_version_prefix
  new_acr_name                   = var.acr_name
  existing_acr_name              = var.acr_name
  existing_acr_resource_group    = var.acr_resource_group
  use_existing_acr               = var.use_existing_acr
  subnet_ids                     = module.kube_network.subnet_ids
  subnet_names                   = module.kube_network.subnet_names
  tags                           = local.tags
  log_analytics_workspace_id     = var.enable_monitoring ? azurerm_log_analytics_workspace.test[0].id : null
}

resource "azurerm_log_analytics_workspace" "test" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "${var.env_prefix}-chaos-evidence"
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
  tags                = merge(local.tags, { "chaos-excluded" = "true" })
}
