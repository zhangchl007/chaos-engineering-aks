terraform {
  required_version = ">= 1.9.0"
  backend "local" {
    path = "../../local-state/dev/cluster.tfstate"
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.55.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.38.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
}

data "azurerm_kubernetes_cluster" "target" {
  name                = var.cluster_name
  resource_group_name = var.cluster_resource_group_name
}

locals {
  exec_args = [
    "get-token", "--login", var.kubelogin_login_mode,
    "--environment", "AzurePublicCloud",
    "--tenant-id", var.tenant_id,
    "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"
  ]
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.target.kube_config[0].host
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.target.kube_config[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = local.exec_args
  }
}

provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.target.kube_config[0].host
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.target.kube_config[0].cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args        = local.exec_args
    }
  }
}
