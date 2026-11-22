terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

locals {
  agfc_name = lower(replace("${var.env_prefix}-${var.agfc_name}", "_", "-"))
  tags = merge(
    { for key, value in {
      Environment = var.env_prefix
      ManagedBy   = "Terraform"
      Component   = "agfc"
    } : key => value if !contains([for tag_key in keys(var.tags) : lower(tag_key)], lower(key)) },
    var.tags
  )
}

# Application Gateway for Containers
resource "azurerm_application_load_balancer" "agfc" {
  name                = local.agfc_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  lifecycle {
    precondition {
      condition     = var.allow_public_frontend && var.frontend_ip == null
      error_message = "AzureRM 4.55.0 configures only the default public AGFC frontend. Explicit allow_public_frontend consent is required; private frontend_ip is unsupported by this module."
    }
  }
}

# Associate AGFC with the subnet
resource "azurerm_application_load_balancer_subnet_association" "agfc" {
  name                         = "${local.agfc_name}-subnet-assoc"
  application_load_balancer_id = azurerm_application_load_balancer.agfc.id
  subnet_id                    = var.subnet_id
}

# Frontend for AGFC
resource "azurerm_application_load_balancer_frontend" "agfc" {
  name                         = var.frontend_name
  application_load_balancer_id = azurerm_application_load_balancer.agfc.id
}
