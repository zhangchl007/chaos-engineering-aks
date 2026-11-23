resource "azurerm_private_dns_zone" "redis" {
  count               = var.components.redis ? 1 : 0
  name                = "privatelink.redis.azure.net"
  resource_group_name = azurerm_resource_group.kube.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  count                 = var.components.redis ? 1 : 0
  name                  = "${var.env_prefix}-redis"
  resource_group_name   = azurerm_resource_group.kube.name
  private_dns_zone_name = azurerm_private_dns_zone.redis[0].name
  virtual_network_id    = module.kube_network.vnet_id
  registration_enabled  = false
}

module "redis" {
  count                     = var.components.redis ? 1 : 0
  source                    = "./modules/redis"
  resource_group_name       = azurerm_resource_group.kube.name
  location                  = var.location
  env_prefix                = var.env_prefix
  redis_name                = var.redis_name
  redis_sku_name            = var.redis_sku_name
  redis_client_protocol     = var.redis_client_protocol
  redis_minimum_tls_version = var.redis_minimum_tls_version
  redis_enable_non_ssl_port = var.redis_enable_non_ssl_port
  redis_eviction_policy     = var.redis_eviction_policy
  database_name             = var.redis_database_name
  modules                   = var.redis_modules
  use_azapi                 = var.redis_use_azapi
  subnet_id                 = module.kube_network.subnet_ids["privateendpoint-subnet"]
  private_dns_zone_id       = azurerm_private_dns_zone.redis[0].id
  tags                      = local.tags
}

moved {
  from = module.redis
  to   = module.redis[0]
}

locals {
  mysql_admin_password      = var.mysql_admin_password == null || var.mysql_admin_password == "" ? one(random_password.mysql_admin[*].result) : var.mysql_admin_password
  postgresql_admin_password = var.postgresql_admin_password == null || var.postgresql_admin_password == "" ? one(random_password.postgresql_admin[*].result) : var.postgresql_admin_password
}

resource "random_password" "mysql_admin" {
  count = var.components.mysql && nonsensitive(var.mysql_admin_password == null || var.mysql_admin_password == "") ? 1 : 0

  length           = 32
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#%*-_=+"
}

resource "random_password" "postgresql_admin" {
  count = var.components.postgresql && nonsensitive(var.postgresql_admin_password == null || var.postgresql_admin_password == "") ? 1 : 0

  length           = 32
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#%*-_=+"
}

module "mysql" {
  count               = var.components.mysql ? 1 : 0
  source              = "./modules/mysql"
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  env_prefix          = var.env_prefix
  subnet_ids          = module.kube_network.subnet_ids
  server_name         = var.mysql_server_name
  admin_user          = var.mysql_admin_user
  admin_password      = local.mysql_admin_password
  mysql_version       = var.mysql_version
  database_name       = var.mysql_database_name
  sku_name            = var.mysql_sku_name
  storage_size        = var.mysql_storage_size
  zone                = var.mysql_zone
  availability_mode   = var.mysql_availability_mode
  tags                = local.tags
}

module "postgresql" {
  count                  = var.components.postgresql ? 1 : 0
  source                 = "./modules/postgresql"
  name                   = "${var.env_prefix}-postgresql"
  resource_group_name    = azurerm_resource_group.kube.name
  location               = var.location
  delegated_subnet_id    = module.kube_network.subnet_ids["postgresql-subnet"]
  private_dns_zone_id    = azurerm_private_dns_zone.service["postgres"].id
  administrator_login    = "fixtureadmin"
  administrator_password = local.postgresql_admin_password
  tags                   = local.tags
  depends_on             = [azurerm_private_dns_zone_virtual_network_link.service["postgres"]]
}

module "cosmosdb" {
  count               = var.components.cosmosdb || var.retain_cosmos_network ? 1 : 0
  source              = "./modules/cosmosdb"
  create_account      = var.components.cosmosdb
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  account_location    = var.cosmos_location
  env_prefix          = var.env_prefix
  subnet_ids          = module.kube_network.subnet_ids
  account_name        = var.cosmos_account_name
  database_name       = var.cosmos_database_name
  container_name      = var.cosmos_container_name
  throughput          = var.cosmos_throughput
  tags                = local.tags
}

module "eventhub" {
  count                   = var.components.eventhub ? 1 : 0
  source                  = "./modules/eventhub"
  resource_group_name     = azurerm_resource_group.kube.name
  location                = var.location
  env_prefix              = var.env_prefix
  subnet_ids              = module.kube_network.subnet_ids
  namespace_name          = var.eventhub_namespace_name
  eventhub_name           = var.eventhub_name
  sku_name                = var.eventhub_sku_name
  capacity                = var.eventhub_capacity
  message_retention       = var.eventhub_message_retention
  partition_count         = var.eventhub_partition_count
  enable_private_endpoint = var.eventhub_enable_private_endpoint
  private_dns_zone_id     = azurerm_private_dns_zone.service["messaging"].id
  tags                    = local.tags
}

module "servicebus" {
  count               = var.components.servicebus ? 1 : 0
  source              = "./modules/servicebus"
  name                = "${var.env_prefix}-servicebus"
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  subnet_id           = module.kube_network.subnet_ids["privateendpoint-subnet"]
  private_dns_zone_id = azurerm_private_dns_zone.service["messaging"].id
  tags                = local.tags
}

module "storage" {
  count               = var.components.storage ? 1 : 0
  source              = "./modules/storage"
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  subnet_id           = module.kube_network.subnet_ids["privateendpoint-subnet"]
  private_dns_zone_id = azurerm_private_dns_zone.service["blob"].id
  tags                = local.tags
}

module "vm" {
  count               = var.components.vm ? 1 : 0
  source              = "./modules/vm"
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  env_prefix          = var.env_prefix
  vnet_id             = module.kube_network.vnet_id
  subnet_ids          = module.kube_network.subnet_ids
  vms = {
    for name, config in var.vms : name => merge(config, {
      protect_public_ssh      = name == "jumpserver" && config.enable_public_ip
      public_ssh_source_cidrs = name == "jumpserver" ? var.jumpserver_ssh_source_cidrs : []
    })
  }
  tags = local.tags
}

module "agfc" {
  count                 = var.components.agfc ? 1 : 0
  source                = "./modules/agfc"
  resource_group_name   = azurerm_resource_group.kube.name
  location              = var.location
  env_prefix            = var.env_prefix
  vnet_id               = module.kube_network.vnet_id
  subnet_id             = module.kube_network.subnet_ids["ingress-subnet"]
  frontend_ip           = null
  allow_public_frontend = var.allow_public_agfc
}

output "agfc" {
  description = "Azure AGFC controller and association IDs for the separate cluster stage; null when disabled."
  value = var.components.agfc ? {
    controller_id  = module.agfc[0].agfc_id
    association_id = module.agfc[0].subnet_association_id
  } : null
}

resource "random_id" "azure_cache" {
  count       = var.components.azure_cache && var.azure_cache_name == null ? 1 : 0
  byte_length = 8
}

resource "azurerm_private_dns_zone" "azure_cache" {
  count               = var.components.azure_cache ? 1 : 0
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = azurerm_resource_group.kube.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "azure_cache" {
  count                 = var.components.azure_cache ? 1 : 0
  name                  = "${var.env_prefix}-azure-cache"
  resource_group_name   = azurerm_resource_group.kube.name
  private_dns_zone_name = azurerm_private_dns_zone.azure_cache[0].name
  virtual_network_id    = module.kube_network.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_user_assigned_identity" "azure_cache" {
  count               = var.components.azure_cache ? 1 : 0
  name                = "${var.env_prefix}-cache-verifier"
  resource_group_name = azurerm_resource_group.kube.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "azure_cache" {
  count               = var.components.azure_cache ? 1 : 0
  name                = "azure-cache-verifier"
  resource_group_name = azurerm_resource_group.kube.name
  parent_id           = azurerm_user_assigned_identity.azure_cache[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:chaos-verification:azure-cache-verifier"
}

module "redis_legacy" {
  source                       = "./modules/redis-legacy"
  existing_name                = var.legacy_redis_name
  existing_resource_group_name = var.legacy_redis_resource_group
  enable_new                   = var.components.azure_cache
  eligibility_confirmed        = var.azure_cache_eligibility_confirmed
  name                         = var.components.azure_cache ? (var.azure_cache_name != null ? var.azure_cache_name : "${var.env_prefix}-cache-${random_id.azure_cache[0].hex}") : null
  resource_group_name          = azurerm_resource_group.kube.name
  location                     = var.location
  subnet_id                    = var.components.azure_cache ? module.kube_network.subnet_ids["privateendpoint-subnet"] : null
  private_dns_zone_id          = var.components.azure_cache ? azurerm_private_dns_zone.azure_cache[0].id : null
  access_policy_assignments = var.components.azure_cache ? {
    CacheVerifier = azurerm_user_assigned_identity.azure_cache[0].principal_id
  } : {}
  tags = local.tags
}

variable "legacy_redis_name" {
  type        = string
  description = "Optional approved existing legacy cache reference; never inferred from Managed Redis."
  default     = null
}
variable "legacy_redis_resource_group" {
  type        = string
  description = "Resource group of the separately approved existing legacy cache."
  default     = null
}

locals {
  fixture_ids = {
    mysql       = var.components.mysql ? module.mysql[0].mysql_server_id : null
    postgresql  = var.components.postgresql ? module.postgresql[0].server_id : null
    cosmosdb    = var.components.cosmosdb ? module.cosmosdb[0].cosmosdb_account_id : null
    redis       = var.components.redis ? module.redis[0].redis_cluster_id : null
    azure_cache = var.components.azure_cache ? module.redis_legacy.redis_id : null
    legacy      = module.redis_legacy.redis_id
    eventhub    = var.components.eventhub ? module.eventhub[0].eventhub_namespace_id : null
    servicebus  = var.components.servicebus ? module.servicebus[0].namespace_id : null
    storage     = var.components.storage ? module.storage[0].storage_account_id : null
    vm          = var.components.vm ? module.vm[0].vm_ids : {}
  }
}

output "fixture_ids" {
  description = "Selected resource IDs, null for deliberately disabled fixture families."
  value       = local.fixture_ids
}

output "azure_cache" {
  description = "New classic Azure Cache TLS endpoint and dedicated AKS workload identity; null when new creation is disabled. IDs do not establish business readiness."
  value = var.components.azure_cache ? {
    id              = module.redis_legacy.redis_id
    hostname        = module.redis_legacy.redis_hostname
    port            = module.redis_legacy.redis_ssl_port
    client_id       = azurerm_user_assigned_identity.azure_cache[0].client_id
    namespace       = "chaos-verification"
    service_account = "azure-cache-verifier"
  } : null
}

output "vm_connections" {
  description = "VM connection/SSH access status and NSG IDs; public jumpserver uses a separate SSH guard, RocketMQ remains private. Not business readiness evidence."
  value = var.components.vm ? {
    jumpserver      = module.vm[0].jumpserver_details
    rocketmq        = module.vm[0].rocketmq_details
    nsgs            = module.vm[0].vm_network_security_groups
    public_ssh_nsgs = module.vm[0].public_ssh_network_security_groups
  } : null
}
