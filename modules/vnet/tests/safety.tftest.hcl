mock_provider "azurerm" {}
variables {
  resource_group_name = "fixture"
  location            = "eastus"
  vnet_name           = "fixture"
  address_space       = ["10.0.0.0/16"]
  subnets = [
    { name = "node-subnet", address_prefixes = ["10.0.0.0/24"], delegation = "" }
  ]
}
run "dedicated_delegation" {
  command = plan
  variables {
    subnets = [{ name = "mysql-subnet", address_prefixes = ["10.0.1.0/24"], delegation = "Microsoft.DBforMySQL/flexibleServers" }]
  }
}
run "duplicate_names_rejected" {
  command = plan
  variables {
    subnets = [
      { name = "same", address_prefixes = ["10.0.0.0/24"], delegation = "" },
      { name = "same", address_prefixes = ["10.0.1.0/24"], delegation = "" }
    ]
  }
  expect_failures = [var.subnets]
}
run "invalid_cidr_rejected" {
  command = plan
  variables {
    subnets = [{ name = "invalid", address_prefixes = ["invalid"], delegation = "" }]
  }
  expect_failures = [var.subnets]
}
