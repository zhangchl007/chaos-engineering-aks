output "identity_id" {
  description = "Controller UAMI Azure resource ID."
  value       = azurerm_user_assigned_identity.controller.id
}

output "identity_client_id" {
  description = "Workload federation client ID (not the RBAC principal ID)."
  value       = azurerm_user_assigned_identity.controller.client_id
}

output "identity_principal_id" {
  description = "Controller UAMI principal object ID used for RBAC."
  value       = azurerm_user_assigned_identity.controller.principal_id
}

output "namespace" {
  description = "Official ALB controller namespace."
  value       = helm_release.controller.namespace
}

output "association_id" {
  description = "Platform-owned association referenced by later BYO Gateway configuration."
  value       = var.association_id
}
