variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Location in which to deploy the network"
  type        = string
}

variable "vnet_name" {
  description = "VNET name"
  type        = string
}

variable "address_space" {
  description = "VNET address space"
  type        = list(string)
}

variable "subnets" {
  description = "Subnets configuration"
  type = list(object({
    name             = string
    address_prefixes = list(string)
    delegation       = string
  }))
  validation {
    condition     = length(var.subnets) == length(distinct([for s in var.subnets : s.name])) && alltrue([for s in var.subnets : alltrue([for cidr in s.address_prefixes : can(cidrhost(cidr, 0))])])
    error_message = "Subnets must have unique names and valid CIDRs."
  }
  validation {
    condition = alltrue([for s in var.subnets : contains([
      "", "Microsoft.ContainerService/managedClusters", "Microsoft.ServiceNetworking/trafficControllers",
      "Microsoft.DBforMySQL/flexibleServers", "Microsoft.DBforPostgreSQL/flexibleServers"
    ], s.delegation)])
    error_message = "Select a supported dedicated subnet delegation."
  }
}
