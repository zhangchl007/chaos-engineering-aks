data "azurerm_resource_group" "nodes" {
  count = var.ingress_mode == "agfc" ? 1 : 0
  name  = data.azurerm_kubernetes_cluster.target.node_resource_group
}

module "ingress" {
  count                   = var.ingress_mode == "nginx" ? 1 : 0
  source                  = "../../modules/ingress"
  resource_group_name     = var.cluster_resource_group_name
  location                = data.azurerm_kubernetes_cluster.target.location
  env_prefix              = var.env_prefix
  tls_secret_name         = var.nginx_tls_secret_name
  allow_unsupported_nginx = var.allow_unsupported_nginx
}

module "argocd" {
  count              = var.enable_argocd ? 1 : 0
  source             = "../../modules/argocd"
  allow_legacy_chart = var.allow_legacy_argocd_chart
}

module "agfc_controller" {
  for_each                  = var.ingress_mode == "agfc" && var.agfc != null ? { active = var.agfc } : {}
  source                    = "../../modules/agfc-controller"
  resource_group_name       = each.value.resource_group_name
  location                  = data.azurerm_kubernetes_cluster.target.location
  identity_name             = each.value.identity_name
  oidc_issuer_url           = data.azurerm_kubernetes_cluster.target.oidc_issuer_url
  node_resource_group_id    = data.azurerm_resource_group.nodes[0].id
  agfc_resource_group_id    = each.value.resource_group_id
  association_id            = each.value.association_id
  association_subnet_id     = each.value.association_subnet_id
  workload_identity_enabled = each.value.workload_identity_enabled
}
