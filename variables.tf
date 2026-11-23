variable "location" {
  type        = string
  description = "The resource group location"
  default     = "West US 2"
}

variable "kube_vnet_name" {
  type        = string
  description = "AKS VNET name"
  default     = "aks-kubevnet"
}

variable "kube_version_prefix" {
  type        = string
  description = "AKS Kubernetes version prefix. Formatted '[Major].[Minor]' like '1.18'. Patch version part (as in '[Major].[Minor].[Patch]') will be set to latest automatically."
  default     = "1.28"
}

variable "kube_resource_group_name" {
  type        = string
  description = "The resource group name to be created"
  default     = "rg-aks-tfdemo"
}

variable "nodepool_nodes_count" {
  type        = number
  description = "Default nodepool nodes count"
  default     = 2
}

variable "nodepool_vm_size" {
  type        = string
  description = "Default nodepool VM size"
  default     = "Standard_D4_v3"
}

variable "network_dns_service_ip" {
  type        = string
  description = "CNI DNS service IP"
  default     = "178.51.0.10"
}

variable "network_service_cidr" {
  type        = string
  description = "CNI service cidr"
  default     = "178.51.0.0/16"
}

variable "address_space" {
  description = "Vnet address_space"
  type        = list(string)

  default = ["10.4.0.0/20"]

}

variable "username" {
  type        = string
  description = "The username for the AKS cluster"
  default     = "azureuser"

}

variable "ssh_public_key" {
  type        = string
  description = "Optional path to a public SSH key; empty disables the AKS SSH profile."
  default     = ""
}

variable "cluster_name" {
  type        = string
  description = "AKS Cluster Name"
  default     = "private-aks"
}

variable "env_prefix" {
  type        = string
  description = "DNS Prefix"
  default     = "tf"
}
variable "subnets" {
  description = "The list of subnets to be created"
  type = list(object({
    name             = string
    address_prefixes = list(string)
    delegation       = string
  }))

  default = [
    {
      name : "node-subnet"
      address_prefixes : ["10.4.0.0/24"]
      delegation = ""
    },
    {
      name : "pod-subnet"
      address_prefixes : ["10.4.1.0/24"]
      delegation = "Microsoft.ContainerService/managedClusters"
    },
    {
      name : "appgw-subnet"
      address_prefixes : ["10.4.2.0/24"]
      delegation = ""
    },

    {
      name : "ingress-subnet"
      address_prefixes : ["10.4.3.0/24"]
      delegation = "Microsoft.ServiceNetworking/trafficControllers"
    },
    {
      name             = "privateendpoint-subnet"
      address_prefixes = ["10.4.4.0/24"]
      delegation       = ""
    },
    {
      name             = "mysql-subnet"
      address_prefixes = ["10.4.5.0/24"]
      delegation       = "Microsoft.DBforMySQL/flexibleServers"
    },
    {
      name             = "postgresql-subnet"
      address_prefixes = ["10.4.6.0/24"]
      delegation       = "Microsoft.DBforPostgreSQL/flexibleServers"
    },
    {
      name             = "vm-subnet"
      address_prefixes = ["10.4.7.0/24"]
      delegation       = ""
    }
  ]
}

variable "acr_name" {
  description = "Name of the existing Azure Container Registry"
  type        = string
  default     = "" # Empty string means create a new ACR
}
variable "use_existing_acr" {
  type        = bool
  description = "Whether to use an existing Azure Container Registry (true) or create a new one (false)"
  default     = false
}

variable "acr_resource_group" {
  description = "Resource group of the existing Azure Container Registry"
  type        = string
  default     = "" # If not provided, use the AKS resource group
}

variable "argocd_name" {
  description = "The name of the ArgoCD release."
  type        = string
  default     = "argocd"
}
variable "argocd_namespace" {
  description = "The namespace where ArgoCD will be installed."
  type        = string
  default     = "argocd"
}
variable "argocd_repository" {
  description = "The Helm repository for ArgoCD."
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}
variable "argocd_chart" {
  description = "The Helm chart for ArgoCD."
  type        = string
  default     = "argo-cd"
}
variable "argocd_version" {
  description = "The version of the ArgoCD Helm chart."
  type        = string
  default     = "5.24.1"
}
variable "redis_name" {
  description = "Managed Redis logical name"
  type        = string
  default     = "redis"
}

variable "redis_sku_name" {
  description = "Managed Redis SKU"
  type        = string
  default     = "Balanced_B0"
}

variable "redis_client_protocol" {
  description = "Managed Redis client protocol"
  type        = string
  default     = "Encrypted"
}

variable "redis_minimum_tls_version" {
  description = "Managed Redis minimum TLS version"
  type        = string
  default     = "1.2"
}

variable "redis_enable_non_ssl_port" {
  description = "Enable plaintext port 6379"
  type        = bool
  default     = false
}

variable "redis_eviction_policy" {
  description = "Managed Redis eviction policy"
  type        = string
  default     = "allkeys-lru"
}

variable "agfc_name" {
  description = "Application Gateway for Containers name"
  type        = string
  default     = "agfc"
}

variable "agfc_frontend_name" {
  description = "AGFC Frontend name"
  type        = string
  default     = "agfc-frontend"
}

variable "agfc_frontend_ip" {
  description = "Frontend IP for AGFC"
  type        = string
  default     = ""
}

variable "redis_database_name" {
  description = "Name of the Redis database"
  type        = string
  default     = "default"
}

variable "redis_modules" {
  description = "List of Redis modules to enable"
  type        = list(string)
  default     = ["RedisBloom", "RedisTimeSeries"]
}

variable "redis_use_azapi" {
  description = "Whether to use AzAPI for Redis deployment"
  type        = bool
  default     = true
}

variable "bootstrap_rbac_enabled" {
  description = "If true, Terraform will create an RBAC role assignment at the resource group scope for the chosen principal (useful to bootstrap access for resources like Redis Enterprise)."
  type        = bool
  default     = false
}

variable "bootstrap_rbac_principal_object_id" {
  description = "Object ID of the principal (user/service principal/managed identity) to grant RBAC to. If null, defaults to the currently-authenticated Terraform identity."
  type        = string
  default     = null
}

variable "bootstrap_rbac_role_definition_name" {
  description = "Built-in role name to assign at the resource group scope (e.g., 'Contributor')."
  type        = string
  default     = "Contributor"
}

variable "cosmos_location" {
  description = "Optional Cosmos account and primary region override; null uses the platform location. Private Endpoint remains in the platform region. Confirm region access and data residency before selecting another region."
  type        = string
  default     = null
  validation {
    condition     = var.cosmos_location == null || can(regex("^[a-z][a-z0-9]+$", var.cosmos_location))
    error_message = "cosmos_location must be null or a lowercase Azure region name without spaces."
  }
}

variable "cosmos_account_name" {
  description = "Cosmos DB account name (without env prefix)"
  type        = string
  default     = "cosmos"
}

variable "cosmos_database_name" {
  description = "Cosmos DB database name"
  type        = string
  default     = "appdb"
}

variable "cosmos_container_name" {
  description = "Cosmos DB container name"
  type        = string
  default     = "items"
}

variable "cosmos_throughput" {
  description = "Cosmos DB manual throughput (RU/s)"
  type        = number
  default     = 400
}

variable "eventhub_namespace_name" {
  description = "Event Hubs namespace base name"
  type        = string
  default     = "ehns"
}

variable "eventhub_name" {
  description = "Event Hub name"
  type        = string
  default     = "events"
}

variable "eventhub_sku_name" {
  description = "Event Hubs namespace SKU"
  type        = string
  default     = "Standard"
}

variable "eventhub_capacity" {
  description = "Throughput units / capacity for Event Hubs namespace"
  type        = number
  default     = 1
}

variable "eventhub_message_retention" {
  description = "Event Hub message retention in days"
  type        = number
  default     = 1
}

variable "eventhub_partition_count" {
  description = "Event Hub partition count"
  type        = number
  default     = 2
}

variable "eventhub_enable_private_endpoint" {
  description = "Whether to create a private endpoint for Event Hubs in mysql-subnet"
  type        = bool
  default     = true
}

variable "mysql_server_name" {
  description = "MySQL Flexible Server name"
  type        = string
  default     = "mysql-server"
}

variable "mysql_admin_user" {
  description = "MySQL admin username"
  type        = string
  default     = "mysqladmin"
}

variable "mysql_admin_password" {
  sensitive   = true
  description = "Optional MySQL admin password override; null or empty generates a strong password for an enabled fixture, stored in protected state."
  type        = string
  default     = null
}

variable "mysql_version" {
  description = "MySQL server version"
  type        = string
  default     = "8.0"
}

variable "mysql_database_name" {
  description = "Default database name"
  type        = string
  default     = "appdb"
}

variable "mysql_sku_name" {
  description = "MySQL compute SKU"
  type        = string
  default     = "GP_Standard_D2ds_v4"
}

variable "mysql_storage_size" {
  description = "MySQL storage size in GB"
  type        = number
  default     = 128
}

variable "mysql_zone" {
  description = "Azure zone for MySQL Flexible Server"
  type        = string
  default     = "1"
}

variable "mysql_availability_mode" {
  description = "Availability mode (e.g. ZoneRedundant, SameZone, Single)"
  type        = string
  default     = "ZoneRedundant"
}

variable "vm_jumpserver_size" {
  description = "VM size for jumpserver"
  type        = string
  default     = "Standard_B2s"
}

variable "vm_jumpserver_username" {
  description = "Admin username for jumpserver"
  type        = string
  default     = "azureuser"
}

variable "vm_enable_jumpserver" {
  description = "Whether to deploy jumpserver"
  type        = bool
  default     = true
}

variable "vm_rocketmq_size" {
  description = "VM size for RocketMQ server"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vm_rocketmq_username" {
  description = "Admin username for RocketMQ server"
  type        = string
  default     = "azureuser"
}

variable "vm_enable_rocketmq" {
  description = "Whether to deploy RocketMQ server"
  type        = bool
  default     = true
}

variable "vms" {
  description = "Map of VMs to create with custom configuration"
  type = map(object({
    vm_name             = string
    vm_size             = string
    subnet_name         = string
    admin_username      = string
    ssh_public_key_path = string
    os_type             = optional(string, "linux")
    image_publisher     = optional(string, "Canonical")
    image_offer         = optional(string, "0001-com-ubuntu-server-focal")
    image_sku           = optional(string, "20_04-lts-gen2")
    image_version       = optional(string)
    enable_public_ip    = optional(bool, false)
    attach_nsg          = optional(bool, true)
    bootstrap_rocketmq  = optional(bool, false)
    nsg_rules = optional(list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_port_range          = string
      destination_port_range     = string
      source_address_prefix      = string
      destination_address_prefix = string
    })), [])
    custom_script = optional(string, "")
    tags          = optional(map(string), {})
  }))
  default = {}
  validation {
    condition = !var.components.vm || (length(var.vms) > 0 && alltrue([
      for vm in values(var.vms) : try(vm.image_version != null && trimspace(vm.image_version) != "" && lower(vm.image_version) != "latest", false)
    ]))
    error_message = "Enabled VM fixtures require explicit VMs with tested immutable image versions; the legacy child-module contract is unchanged."
  }
  validation {
    condition = !var.components.vm || alltrue([
      for name, vm in var.vms : (!vm.enable_public_ip || name == "jumpserver") && (vm.enable_public_ip || !vm.attach_nsg || (anytrue([
        for rule in vm.nsg_rules :
        lower(rule.direction) == "inbound" && lower(rule.access) == "deny" &&
        rule.protocol == "*" && rule.source_address_prefix == "*" &&
        rule.destination_address_prefix == "*" && rule.destination_port_range == "*"
        ]) && alltrue([
        for rule in vm.nsg_rules : lower(rule.direction) != "inbound" || lower(rule.access) != "allow" || (
          can(cidrnetmask(rule.source_address_prefix)) &&
          try(tonumber(split("/", rule.source_address_prefix)[1]) >= 24, false)
        )
      ])))
    ])
    error_message = "Only jumpserver may use a public IP; it receives a dedicated SSH access NSG. Other attached NSGs must deny other inbound traffic and limit Allow sources to /24 or narrower; original templates may remain unattached."
  }
}