terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "azurerm_user_assigned_identity" "controller" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "controller" {
  name                = "alb-controller"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.controller.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.controller_namespace}:alb-controller-sa"
}

locals {
  roles = {
    reader = {
      scope = var.node_resource_group_id
      name  = "Reader"
    }
    configuration_manager = {
      scope = var.agfc_resource_group_id
      name  = "AppGw for Containers Configuration Manager"
    }
    subnet_join = {
      scope = var.association_subnet_id
      name  = "Network Contributor"
    }
  }
}

resource "azurerm_role_assignment" "controller" {
  for_each                         = local.roles
  scope                            = each.value.scope
  role_definition_name             = each.value.name
  principal_id                     = azurerm_user_assigned_identity.controller.principal_id
  skip_service_principal_aad_check = true
}

resource "helm_release" "controller" {
  name             = "alb-controller"
  repository       = "oci://mcr.microsoft.com/application-lb/charts"
  chart            = "alb-controller"
  version          = "1.13.0"
  namespace        = var.controller_namespace
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    albController = {
      namespace = var.controller_namespace
      podIdentity = {
        clientID = azurerm_user_assigned_identity.controller.client_id
      }
    }
  })]

  depends_on = [
    azurerm_federated_identity_credential.controller,
    azurerm_role_assignment.controller
  ]
}
