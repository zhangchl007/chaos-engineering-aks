output "namespace_id" {
  description = "Service Bus namespace resource ID."
  value       = azurerm_servicebus_namespace.this.id
}

output "queue_names" {
  description = "Queue names keyed by stable input keys."
  value       = { for key, queue in azurerm_servicebus_queue.this : key => queue.name }
}

output "topic_names" {
  description = "Topic names keyed by stable input keys; empty unless topics were explicitly requested."
  value       = { for key, topic in azurerm_servicebus_topic.this : key => topic.name }
}

output "private_endpoint_id" {
  description = "Service Bus private endpoint resource ID."
  value       = azurerm_private_endpoint.this.id
}
