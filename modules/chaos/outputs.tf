output "workspace_id" {
  description = "Workspace ID, or null when configuration creation is disabled."
  value       = var.enabled ? azapi_resource.workspace[0].id : null
}

output "runtime_principal_id" {
  description = "Dedicated runtime object ID; not the operator or deployer."
  value       = var.enabled ? azurerm_user_assigned_identity.runtime[0].principal_id : null
}

output "configuration_ids" {
  description = "Configuration IDs for separate validation/authorization; none are run."
  value = merge(
    { for key, resource in azapi_resource.configuration : key => resource.id },
    { for key, resource in azapi_resource.pod_configuration : key => resource.id }
  )
}
