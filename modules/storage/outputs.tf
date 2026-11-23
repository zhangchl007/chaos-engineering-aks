output "storage_account_id" {
  description = "Storage account resource ID."
  value       = azurerm_storage_account.this.id
}

output "blob_endpoint" {
  description = "Blob service endpoint; private DNS must resolve it from the workload network."
  value       = azurerm_storage_account.this.primary_blob_endpoint
  sensitive   = true
}

output "container_name" {
  description = "Private Blob fixture container name."
  value       = azurerm_storage_container.this.name
}
