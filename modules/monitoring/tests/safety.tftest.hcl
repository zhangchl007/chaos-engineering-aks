mock_provider "azurerm" {
  mock_data "azurerm_monitor_diagnostic_categories" {
    defaults = {
      log_category_types = ["kube-apiserver"]
      metrics            = ["AllMetrics"]
    }
  }
}
variables {
  workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.OperationalInsights/workspaces/evidence"
}
run "no_implicit_discovery" {
  command = plan
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.target) == 0
    error_message = "No diagnostic targets may be inferred without explicit selection."
  }
}
run "unsupported_category_rejected" {
  command = plan
  variables {
    targets = {
      aks = {
        resource_id    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.ContainerService/managedClusters/fixture"
        log_categories = ["not-a-real-category"]
      }
    }
  }
  expect_failures = [azurerm_monitor_diagnostic_setting.target["aks"]]
}
