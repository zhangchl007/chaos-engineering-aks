mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  enabled           = false
  name              = "fixture"
  location          = "eastus"
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture"
  tags              = { environment = "test" }
  scopes            = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture"]
}

run "disabled_has_no_resources" {
  command = plan
  assert {
    condition     = length(azapi_resource.workspace) == 0 && length(azapi_resource.scenario) == 0 && length(azurerm_role_assignment.discovery) == 0
    error_message = "Disabled configuration must create neither faults nor permissions."
  }
}

run "empty_targets_rejected" {
  command = plan
  variables {
    scenarios = { restart = { action_id = "microsoft-mysql-restart/1.0", description = "test", target_ids = [] } }
  }
  expect_failures = [var.scenarios]
}

run "subscription_scope_rejected" {
  command = plan
  variables { scopes = ["/subscriptions/00000000-0000-0000-0000-000000000001"] }
  expect_failures = [var.scopes]
}

run "wildcard_permissions_rejected" {
  command = plan
  variables {
    permissions = { target = { target_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.DBforMySQL/flexibleServers/test", actions = ["Microsoft.DBforMySQL/*"] } }
  }
  expect_failures = [var.permissions]
}

run "wrong_resource_type_rejected" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      restart = {
        action_id   = "microsoft-mysql-restart/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Cache/redisEnterprise/test"]
      }
    }
  }
  expect_failures = [azapi_resource.scenario["restart"]]
}

run "case_insensitive_exclusions" {
  command = plan
  variables {
    enabled               = true
    excluded_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourcegroups/fixture/providers/microsoft.dbformysql/flexibleservers/test"]
    scenarios = {
      restart = {
        action_id   = "microsoft-mysql-restart/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.DBforMySQL/flexibleServers/test"]
      }
    }
  }
  expect_failures = [azapi_resource.workspace[0]]
}

run "empty_entity_list_rejected" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      queues = {
        action_id   = "microsoft-servicebus-changequeuestate/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ServiceBus/namespaces/test"]
        parameters  = { desiredState = "Disabled", queues = "[ ]" }
      }
    }
  }
  expect_failures = [azapi_resource.scenario["queues"]]
}

run "bounded_restart_configuration" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      restart = {
        action_id   = "microsoft-mysql-restart/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.DBforMySQL/flexibleServers/test"]
      }
    }

  }
  assert {
    condition     = length(azapi_resource.configuration) == 1 && length(azurerm_role_assignment.target) == 0
    error_message = "Define one allowlisted configuration without guessing broad runtime permissions."
  }
}

run "malformed_entity_json_rejected" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      queues = {
        action_id   = "microsoft-servicebus-changequeuestate/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ServiceBus/namespaces/test"]
        parameters  = { desiredState = "Disabled", queues = "orders" }
      }
    }
  }
  expect_failures = [azapi_resource.scenario["queues"]]
}

run "entity_object_rejected" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      queues = {
        action_id   = "microsoft-servicebus-changequeuestate/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ServiceBus/namespaces/test"]
        parameters  = { desiredState = "Disabled", queues = "{\"orders\":true}" }
      }
    }
  }
  expect_failures = [azapi_resource.scenario["queues"]]
}

run "non_string_entities_rejected" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      queues = {
        action_id   = "microsoft-servicebus-changequeuestate/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ServiceBus/namespaces/test"]
        parameters  = { desiredState = "Disabled", queues = "[1,true,null]" }
      }
    }
  }
  expect_failures = [azapi_resource.scenario["queues"]]
}

run "explicit_queue_list_and_scoped_permissions" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      queues = {
        action_id   = "microsoft-servicebus-changequeuestate/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ServiceBus/namespaces/test"]
        parameters  = { desiredState = "SendDisabled", queues = "[\"orders\"]" }
      }
    }
    permissions = {
      queues = {
        target_id    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ServiceBus/namespaces/test"
        data_actions = ["Microsoft.ServiceBus/namespaces/queues/write"]
      }
    }
  }
  assert {
    condition     = azurerm_role_assignment.target["queues"].scope == var.permissions["queues"].target_id
    error_message = "Runtime permissions must remain on the exact approved target."
  }
}

run "managedredis_database_required" {
  command = plan
  variables {
    enabled                         = true
    allow_destructive_configuration = true
    scenarios = {
      flush = {
        action_id   = "microsoft-managedredis-flushdatabase/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Cache/redisEnterprise/test"]
      }
    }
  }
  expect_failures = [azapi_resource.scenario["flush"]]
}

run "skipped_database_is_not_coverage" {
  command = plan
  variables {
    enabled = true
    scenarios = {
      failover = {
        action_id   = "microsoft-azurepostgresql-failover/1.0"
        description = "test"
        target_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.DBforPostgreSQL/flexibleServers/test"]
        parameters  = { FailoverMode = "PlannedFailover", SkipIneligibleServers = "true" }
      }
    }
  }
  expect_failures = [azapi_resource.scenario["failover"]]
}
