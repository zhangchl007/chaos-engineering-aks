output "redis_cluster_id" {
  description = "Redis Enterprise cluster resource ID"
  value       = var.use_azapi ? azapi_resource.cluster[0].id : null
}

output "redis_cluster_name" {
  description = "Redis Enterprise cluster name"
  value       = var.use_azapi ? azapi_resource.cluster[0].name : null
}

output "redis_database_id" {
  description = "Redis Enterprise database resource ID"
  value       = var.use_azapi ? azapi_resource.database[0].id : null
}

output "redis_database_name" {
  description = "Redis Enterprise database name"
  value       = var.use_azapi ? azapi_resource.database[0].name : null
}

output "redis_database_primary_key" {
  description = "Compatibility output: always null because key authentication is explicitly disabled; use Entra"
  value       = null
  sensitive   = true
}

output "redis_database_secondary_key" {
  description = "Compatibility output: always null because key authentication is explicitly disabled; use Entra"
  value       = null
  sensitive   = true
}

output "redis_hostname" {
  description = "Managed Redis TLS hostname; resolve through caller-owned private DNS"
  value       = var.use_azapi ? "${local.redis_name}.${lower(replace(var.location, " ", ""))}.redis.azure.net" : null
}

output "redis_ssl_port" {
  description = "Managed Redis TLS port"
  value       = var.use_azapi ? 10000 : null
}