variable "diagnostic_profiles" {
  description = "Opt-in diagnostic category selections for enabled fixture keys or aks; no automatic discovery."
  type = map(object({
    log_categories    = optional(set(string), [])
    metric_categories = optional(set(string), [])
  }))
  default = {}
  validation {
    condition     = alltrue([for name in keys(var.diagnostic_profiles) : contains(["aks", "mysql", "postgresql", "cosmosdb", "redis", "eventhub", "servicebus", "storage"], name)])
    error_message = "Choose a known owned fixture key or aks, never shared/recovery resources."
  }
  validation {
    condition     = var.enable_monitoring || length(var.diagnostic_profiles) == 0
    error_message = "Diagnostic profiles require the explicitly enabled evidence workspace."
  }
}

module "diagnostics" {
  count        = var.enable_monitoring ? 1 : 0
  source       = "./modules/monitoring"
  workspace_id = azurerm_log_analytics_workspace.test[0].id
  targets = {
    for name, profile in var.diagnostic_profiles : name => {
      resource_id       = name == "aks" ? module.aks.cluster_id : local.fixture_ids[name]
      log_categories    = profile.log_categories
      metric_categories = profile.metric_categories
    }
  }
}
