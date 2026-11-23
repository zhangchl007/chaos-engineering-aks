output "redis_id" {
  description = "Legacy Microsoft.Cache/redis ID; null only when neither path is selected"
  value       = var.enable_new ? azurerm_redis_cache.fixture[0].id : (local.reference_existing ? data.azapi_resource.existing[0].id : null)
}

output "redis_name" {
  description = "Legacy Redis name; null only when neither path is selected"
  value       = var.enable_new ? azurerm_redis_cache.fixture[0].name : (local.reference_existing ? data.azapi_resource.existing[0].name : null)
}

output "redis_hostname" {
  description = "Legacy Redis hostname from Azure; never a Managed Redis hostname"
  value       = var.enable_new ? azurerm_redis_cache.fixture[0].hostname : (local.reference_existing ? data.azapi_resource.existing[0].output.properties.hostName : null)
}

output "redis_ssl_port" {
  description = "Legacy Redis TLS port from Azure; null when disabled"
  value       = var.enable_new ? azurerm_redis_cache.fixture[0].ssl_port : (local.reference_existing ? data.azapi_resource.existing[0].output.properties.sslPort : null)
}
