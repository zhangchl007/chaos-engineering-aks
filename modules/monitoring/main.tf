terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

variable "workspace_id" {
  type        = string
  description = "Approved private evidence destination with bounded retention and ingestion."
}

variable "targets" {
  description = "Explicit owned targets and approved diagnostic categories; never all discovered resources."
  type = map(object({
    resource_id       = string
    log_categories    = optional(set(string), [])
    metric_categories = optional(set(string), [])
  }))
  default = {}
  validation {
    condition     = alltrue([for t in var.targets : t.resource_id != null && length(setunion(t.log_categories, t.metric_categories)) > 0])
    error_message = "Enable a real selected target and explicitly choose at least one diagnostic category."
  }
}

data "azurerm_monitor_diagnostic_categories" "target" {
  for_each    = var.targets
  resource_id = each.value.resource_id
}

resource "azurerm_monitor_diagnostic_setting" "target" {
  for_each                   = var.targets
  name                       = "chaos-evidence"
  target_resource_id         = each.value.resource_id
  log_analytics_workspace_id = var.workspace_id
  dynamic "enabled_log" {
    for_each = each.value.log_categories
    content { category = enabled_log.value }
  }
  dynamic "enabled_metric" {
    for_each = each.value.metric_categories
    content { category = enabled_metric.value }
  }
  lifecycle {
    precondition {
      condition     = length(setsubtract(each.value.log_categories, toset(data.azurerm_monitor_diagnostic_categories.target[each.key].log_category_types))) == 0
      error_message = "The actual resource does not support the requested log categories."
    }
    precondition {
      condition     = length(setsubtract(each.value.metric_categories, toset(data.azurerm_monitor_diagnostic_categories.target[each.key].metrics))) == 0
      error_message = "The actual resource does not support the requested metric categories."
    }
  }
}

output "diagnostic_ids" {
  description = "Evidence settings; their existence alone is not a test pass."
  value       = { for name, setting in azurerm_monitor_diagnostic_setting.target : name => setting.id }
}
