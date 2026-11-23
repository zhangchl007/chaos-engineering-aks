output "agfc_id" {
  description = "Application Gateway for Containers ID"
  value       = azurerm_application_load_balancer.agfc.id
}

output "agfc_name" {
  description = "Application Gateway for Containers name"
  value       = azurerm_application_load_balancer.agfc.name
}

output "frontend_id" {
  description = "AGFC Frontend ID"
  value       = azurerm_application_load_balancer_frontend.agfc.id
}

output "frontend_name" {
  description = "AGFC Frontend name"
  value       = azurerm_application_load_balancer_frontend.agfc.name
}

output "subnet_association_id" {
  description = "AGFC Subnet association ID"
  value       = azurerm_application_load_balancer_subnet_association.agfc.id
}

output "private_dns_zone_id" {
  description = "Deprecated: no private DNS zone or private frontend is created."
  value       = null
}

output "private_dns_zone_name" {
  description = "Deprecated: no private DNS zone or private frontend is created."
  value       = null
}

output "frontend_fqdn" {
  description = "Public frontend FQDN; does not represent private connectivity."
  value       = azurerm_application_load_balancer_frontend.agfc.fully_qualified_domain_name
}
