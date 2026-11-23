output "server_id" {
  description = "PostgreSQL Flexible Server resource ID"
  value       = azurerm_postgresql_flexible_server.postgresql.id
}

output "fqdn" {
  description = "PostgreSQL Flexible Server fully qualified domain name"
  value       = azurerm_postgresql_flexible_server.postgresql.fqdn
  sensitive   = true
}

output "database_name" {
  description = "Application database name"
  value       = azurerm_postgresql_flexible_server_database.appdb.name
}
