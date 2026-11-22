mock_provider "azurerm" {}

variables {
  resource_group_name   = "fixture-rg"
  location              = "eastus"
  env_prefix            = "fixture"
  vnet_id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/virtualNetworks/fixture"
  subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/fixture-rg/providers/Microsoft.Network/virtualNetworks/fixture/subnets/agfc"
  allow_public_frontend = true
}

run "caller_tag_case_overrides_defaults" {
  command = plan
  variables {
    tags = { environment = "dev", managedby = "caller", component = "caller-component" }
  }
  assert {
    condition     = azurerm_application_load_balancer.agfc.tags == var.tags
    error_message = "AGFC tag defaults must not duplicate case variants supplied by the caller."
  }
}
