# the environment variables env_prefix is critical for the different AKS clusters
env_prefix               = "chaos"
location                 = "UAE North"
kube_vnet_name           = "vnet-uaenorth"
kubernetes_version       = "1.36.5"
kube_resource_group_name = "rg-chaos-test"
cluster_name             = "test-aks-1"
nodepool_nodes_count     = 2
nodepool_vm_size         = "Standard_D4s_v5"
network_dns_service_ip   = "10.96.0.10"
network_service_cidr     = "10.96.0.0/24"
use_existing_acr         = true
acr_name                 = "amllearning02"
acr_resource_group       = "aml-learning-rg"
address_space            = ["172.15.0.0/16"]
username                 = "azureuser"
ssh_public_key           = "~/.ssh/id_rsa.pub"
subnets = [
  {
    name             = "node-subnet"
    address_prefixes = ["172.15.1.0/24"]
    delegation       = ""
  },
  {
    name             = "pod-subnet"
    address_prefixes = ["172.15.2.0/24"]
    delegation       = "Microsoft.ContainerService/managedClusters"
  },
  {
    name             = "appgw-subnet"
    address_prefixes = ["172.15.3.0/24"]
    delegation       = "Microsoft.ServiceNetworking/trafficControllers"
  },
  {
    name             = "ingress-subnet"
    address_prefixes = ["172.15.4.0/24"]
    delegation       = ""
  },
  {
    name             = "mysql-subnet"
    address_prefixes = ["172.15.5.0/24"]
    delegation       = "Microsoft.DBforMySQL/flexibleServers"
  },
  {
    name             = "privateendpoint-subnet"
    address_prefixes = ["172.15.6.0/24"]
    delegation       = ""
  },
  {
    name             = "postgresql-subnet"
    address_prefixes = ["172.15.7.0/27"]
    delegation       = "Microsoft.DBforPostgreSQL/flexibleServers"
  }
]

# Subscription and tenant default to the authenticated Azure context.
# Database passwords are generated when omitted; inject private overrides if needed.
components = {
  mysql       = true
  postgresql  = true
  cosmosdb    = false
  redis       = true
  azure_cache = true
  eventhub    = true
  servicebus  = true
  storage     = true
  vm          = true
}

retain_cosmos_network = true
# Reconfirm eligibility if the target tenant changes.
azure_cache_eligibility_confirmed = true

storage_account_name = "chaosuaenorthlabblob01"

## ingress controller
#ingress_repository = "https://kubernetes.github.io/ingress-nginx"
#ingress_chart      = "ingress-nginx"
#ingress_version    = "4.11.3"
#ingress_namespace = "ingress-nginx"

##argocd
#argocd_repository = "https://argoproj.github.io/argo-helm"
#argocd_chart      = "argo-cd"
#argocd_version    = "7.8.12"
#argocd_namespace = "argocd"
#argocd_name = "argocd"

## Managed Redis
redis_name                = "redis1"
redis_sku_name            = "Balanced_B5"
redis_client_protocol     = "Encrypted"
redis_minimum_tls_version = "1.2"
redis_enable_non_ssl_port = false
redis_eviction_policy     = "allkeys-lru"
redis_database_name       = "default"
redis_modules             = ["RedisBloom", "RedisTimeSeries"]
redis_use_azapi           = true

## Cosmos DB
cosmos_account_name   = "test-cosmos-1"
cosmos_database_name  = "appdb"
cosmos_container_name = "items"
cosmos_throughput     = 400

## Event Hub (optional overrides)
eventhub_namespace_name          = "test-ehns-1"
eventhub_name                    = "events"
eventhub_sku_name                = "Standard"
eventhub_capacity                = 1
eventhub_message_retention       = 1
eventhub_partition_count         = 2
eventhub_enable_private_endpoint = true


## MySQL Flexible Server
mysql_server_name       = "chaos-mysql-1"
mysql_admin_user        = "mysqladmin"
mysql_version           = "8.0.21"
mysql_database_name     = "appdb"
mysql_sku_name          = "GP_Standard_D2ds_v4" # Changed from B_Standard_B2s to Standard_B2s (General Purpose)
mysql_storage_size      = 128                   # GB
mysql_zone              = "1"
mysql_availability_mode = "ZoneRedundant" # High Availability supported

## Virtual Machines (Batch Configuration)
vms = {
  jumpserver = {
    vm_name             = "jumpserver"
    vm_size             = "Standard_B2s"
    subnet_name         = "node-subnet"
    admin_username      = "azureuser"
    ssh_public_key_path = "~/.ssh/id_rsa.pub"
    os_type             = "linux"
    image_offer         = "0001-com-ubuntu-server-jammy"
    image_sku           = "22_04-lts-gen2"
    image_version       = "22.04.202611110"
    enable_public_ip    = true
    attach_nsg          = false
    nsg_rules = [
      {
        name                       = "AllowSSH"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                       = "AllowRDP"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3389"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
    ]
    tags = {
      Purpose = "BastionHost"
    }
  }

  rocketmq = {
    vm_name             = "rocketmq"
    vm_size             = "Standard_D2s_v3"
    subnet_name         = "node-subnet"
    admin_username      = "azureuser"
    ssh_public_key_path = "~/.ssh/id_rsa.pub"
    os_type             = "linux"
    image_offer         = "0001-com-ubuntu-server-jammy"
    image_sku           = "22_04-lts-gen2"
    image_version       = "22.04.202611110"
    enable_public_ip    = false
    attach_nsg          = false
    bootstrap_rocketmq  = true
    nsg_rules = [
      {
        name                       = "AllowSSH"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                       = "AllowRocketMQNameServer"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "9876"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                       = "AllowRocketMQBroker"
        priority                   = 102
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "10911"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                       = "AllowRocketMQBrokerHA"
        priority                   = 103
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "10912"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                       = "AllowRocketMQConsole"
        priority                   = 104
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "8080"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
    ]
    tags = {
      Purpose = "MessageBroker"
    }
  }
}


