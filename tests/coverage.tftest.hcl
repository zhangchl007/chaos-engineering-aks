mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ManagedIdentity/userAssignedIdentities/cache-verifier"
      principal_id = "00000000-0000-0000-0000-000000000005"
      client_id    = "00000000-0000-0000-0000-000000000006"
    }
  }
  mock_resource "azurerm_redis_cache" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Cache/redis/cache-fixture"
      hostname = "cache-fixture.redis.cache.windows.net"
      ssl_port = 6380
    }
  }
}
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
    }
  }
}
mock_provider "random" {}

override_module {
  target = module.aks
  outputs = {
    cluster_id          = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/fixture"
    node_resource_group = "fixture-nodes"
    oidc_issuer_url     = "https://issuer.invalid"
    acr_login_server    = "fixture.invalid"
  }
}
override_module {
  target = module.kube_network
  outputs = {
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture"
    subnet_ids = {
      node-subnet            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/node"
      pod-subnet             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/pod"
      privateendpoint-subnet = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/endpoints"
      mysql-subnet           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/mysql"
      postgresql-subnet      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/postgresql"
      vm-subnet              = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/vm"
      ingress-subnet         = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/virtualNetworks/fixture/subnets/ingress"
    }
    subnet_names = { node-subnet = "node", pod-subnet = "pod" }
  }
}
variables {
  kubernetes_version = "1.35.1"
  enable_monitoring  = false
}

run "reserved_tags_are_case_insensitive" {
  command = plan
  variables {
    tags = {
      Environment = "caller-environment"
      MANAGED_BY  = "caller-manager"
      Owner       = "caller-team"
    }
  }
  assert {
    condition     = tomap(local.tags) == tomap({ environment = var.environment, managed_by = "terraform", Owner = "caller-team" }) && alltrue([for zone in azurerm_private_dns_zone.service : zone.tags == tomap(local.tags)])
    error_message = "Root-owned tags must override case variants without duplicating keys or changing custom tag names/values."
  }
}

run "reject_case_duplicate_tags" {
  command = plan
  variables {
    tags = { Environment = "dev", environment = "test" }
  }
  expect_failures = [var.tags]
}

run "new_azure_cache_is_distinct_and_has_workload_access" {
  command = apply
  variables {
    components                        = { azure_cache = true, redis = true }
    azure_cache_eligibility_confirmed = true
  }
  override_module {
    target  = module.redis[0]
    outputs = { redis_cluster_id = "mock-managed-redis-id" }
  }
  override_resource {
    target = azurerm_private_dns_zone.azure_cache[0]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Network/privateDnsZones/privatelink.redis.cache.windows.net"
    }
  }
  assert {
    condition     = output.fixture_ids.azure_cache != null && output.fixture_ids.redis == "mock-managed-redis-id" && output.fixture_ids.azure_cache != output.fixture_ids.redis
    error_message = "New classic Azure Cache must not replace or alias the Managed Redis fixture."
  }
  assert {
    condition     = azurerm_private_dns_zone.azure_cache[0].name == "privatelink.redis.cache.windows.net" && azurerm_private_dns_zone.redis[0].name == "privatelink.redis.azure.net" && length(azurerm_private_dns_zone_virtual_network_link.azure_cache) == 1
    error_message = "Classic Azure Cache requires its own DNS zone and VNet link."
  }
  assert {
    condition     = output.azure_cache.client_id == azurerm_user_assigned_identity.azure_cache[0].client_id && azurerm_federated_identity_credential.azure_cache[0].subject == "system:serviceaccount:chaos-verification:azure-cache-verifier"
    error_message = "Cache data access must use a dedicated AKS workload identity, not the Terraform identity."
  }
}

run "enabled_vms_reject_unbounded_inbound_access" {
  command = plan
  variables {
    components = { vm = true }
    vms = {
      jumpserver = {
        vm_name             = "jumpserver"
        vm_size             = "Standard_D2s_v5"
        subnet_name         = "node-subnet"
        admin_username      = "testuser"
        ssh_public_key_path = "modules/vm/tests/fixtures/test.pub"
        image_version       = "22.04.202611110"
        nsg_rules = [{
          name                       = "UnboundedSSH"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "22"
          source_address_prefix      = "0.0.0.0/0"
          destination_address_prefix = "*"
        }]
      }
    }
  }
  expect_failures = [var.vms]
}
run "cosmos_override_keeps_platform_region" {
  command = plan
  variables {
    components      = { cosmosdb = true }
    location        = "eastus"
    cosmos_location = "westus2"
  }
  assert {
    condition     = azurerm_resource_group.kube.location == var.location
    error_message = "Selecting a Cosmos-only region must not relocate the platform resource group."
  }
}

run "reject_empty_cosmos_region" {
  command = plan
  variables {
    cosmos_location = ""
  }
  expect_failures = [var.cosmos_location]
}

run "cosmos_network_retained_with_business_disabled" {
  command = plan
  variables {
    components            = {}
    retain_cosmos_network = true
  }
  assert {
    condition     = length(module.cosmosdb) == 1 && module.cosmosdb[0].cosmosdb_account_id == null && output.fixture_ids.cosmosdb == null
    error_message = "Network retention must keep the module without provisioning an account or reporting a live Cosmos fixture."
  }
}

run "extra_fixtures_default_off" {
  command = plan
  assert {
    condition     = local.subscription_id == "00000000-0000-0000-0000-000000000001" && local.tenant_id == "00000000-0000-0000-0000-000000000002"
    error_message = "Omitted subscription and tenant inputs must use the authenticated context."
  }
  assert {
    condition     = alltrue([for key in ["mysql", "postgresql", "cosmosdb", "redis", "eventhub", "servicebus", "storage"] : output.fixture_ids[key] == null])
    error_message = "Extra fixtures must not be provisioned implicitly."
  }
  assert {
    condition     = length(module.cosmosdb) == 0
    error_message = "Fresh defaults must not create Cosmos network resources without explicit retention."
  }
  assert {
    condition     = length(random_password.mysql_admin) == 0 && length(random_password.postgresql_admin) == 0
    error_message = "Disabled databases must not create password resources."
  }
  assert {
    condition     = output.mysql_admin_password == null && output.postgresql_admin_password == null
    error_message = "Disabled databases must not expose administrator passwords."
  }
}

run "explicit_azure_context_overrides" {
  command = plan
  variables {
    subscription_id = "00000000-0000-0000-0000-000000000003"
    tenant_id       = "00000000-0000-0000-0000-000000000004"
  }
  assert {
    condition     = local.subscription_id == var.subscription_id && local.tenant_id == var.tenant_id && length(data.azapi_client_config.current) == 0
    error_message = "Explicit context inputs must take precedence without a context lookup."
  }
}

run "subscription_override_keeps_context_tenant" {
  command = plan
  variables {
    subscription_id = "00000000-0000-0000-0000-000000000003"
  }
  assert {
    condition     = local.subscription_id == var.subscription_id && local.tenant_id == "00000000-0000-0000-0000-000000000002"
    error_message = "A subscription override must retain the authenticated tenant when omitted."
  }
}

run "expanded_data_fixture_wiring" {
  command = plan
  variables {
    components = {
      mysql    = true, postgresql = true, cosmosdb = true, redis = true,
      eventhub = true, servicebus = true, storage = true
    }
    mysql_admin_password      = "MockOnly-NotARealCredential123!"
    postgresql_admin_password = "MockOnly-NotARealCredential123!"
    storage_account_name      = "fixture123"
  }
  override_module {
    target  = module.mysql[0]
    outputs = { mysql_server_id = "mock-mysql-id" }
  }
  override_module {
    target  = module.postgresql[0]
    outputs = { server_id = "mock-postgresql-id" }
  }
  override_module {
    target  = module.cosmosdb[0]
    outputs = { cosmosdb_account_id = "mock-cosmos-id" }
  }
  override_module {
    target  = module.redis[0]
    outputs = { redis_cluster_id = "mock-managed-redis-id" }
  }
  override_module {
    target  = module.eventhub[0]
    outputs = { eventhub_namespace_id = "mock-eventhub-id" }
  }
  override_module {
    target  = module.servicebus[0]
    outputs = { namespace_id = "mock-servicebus-id" }
  }
  override_module {
    target  = module.storage[0]
    outputs = { storage_account_id = "mock-storage-id" }
  }
  assert {
    condition     = alltrue([for key in ["mysql", "postgresql", "cosmosdb", "redis", "eventhub", "servicebus", "storage"] : output.fixture_ids[key] != null])
    error_message = "Every selected data-family module must be wired to its narrow output."
  }
  assert {
    condition     = length(random_password.mysql_admin) == 0 && length(random_password.postgresql_admin) == 0
    error_message = "Explicit database passwords must not be replaced by generated passwords."
  }
  assert {
    condition     = output.mysql_admin_password == var.mysql_admin_password && output.postgresql_admin_password == var.postgresql_admin_password
    error_message = "Password outputs must expose the explicit credentials actually supplied to enabled databases."
  }
}

run "enabled_databases_generate_missing_passwords" {
  command = plan
  variables {
    components                = { mysql = true, postgresql = true }
    mysql_admin_password      = ""
    postgresql_admin_password = null
  }
  override_module {
    target  = module.mysql[0]
    outputs = { mysql_server_id = "mock-mysql-id" }
  }
  override_module {
    target  = module.postgresql[0]
    outputs = { server_id = "mock-postgresql-id" }
  }
  assert {
    condition     = length(random_password.mysql_admin) == 1 && length(random_password.postgresql_admin) == 1
    error_message = "Enabled databases with empty or null passwords must generate separate password resources."
  }
}
