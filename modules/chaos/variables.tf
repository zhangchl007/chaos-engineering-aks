variable "enabled" {
  type        = bool
  description = "Create configuration only; never starts a fault."
  default     = false
}

variable "name" {
  type        = string
  description = "Dedicated non-production Workspace name."
}

variable "resource_group_id" {
  type        = string
  description = "Resource group owning the Workspace."
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "Supply the explicit Workspace resource group ID."
  }
}

variable "location" {
  type        = string
  description = "Verified Workspace region."
}

variable "tags" {
  type        = map(string)
  description = "Ownership and non-production environment metadata."
  default     = {}
}

variable "scopes" {
  type        = set(string)
  description = "Approved resource-group discovery scopes; no subscription-wide scope."
  default     = []
  validation {
    condition     = alltrue([for id in var.scopes : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", id))])
    error_message = "Discovery must be limited to explicit resource groups."
  }
}

variable "scenarios" {
  description = "One bounded service-direct or agent-verified VM pressure Action per configuration, with explicit targets."
  type = map(object({
    action_id        = string
    description      = string
    duration_minutes = optional(number, 1)
    target_ids       = set(string)
    parameters       = optional(map(string), {})
    locations        = optional(set(string), [])
    zones            = optional(set(string), [])
  }))
  default = {}
  validation {
    condition     = alltrue([for s in var.scenarios : length(s.target_ids) > 0 && alltrue([for id in s.target_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[^/]+/.+$", id))])])
    error_message = "Every Scenario needs an explicit non-empty resource allowlist."
  }
  validation {
    condition     = alltrue([for s in var.scenarios : s.duration_minutes >= 1 && s.duration_minutes <= 5 && floor(s.duration_minutes) == s.duration_minutes])
    error_message = "Initial Action durations must be whole minutes between 1 and 5."
  }
  validation {
    condition     = alltrue([for s in var.scenarios : length(s.zones) <= 1 && alltrue([for z in s.zones : contains(["1", "2", "3"], z)]) && (length(s.zones) == 0 || length(s.locations) > 0)])
    error_message = "Initial zone tests must select one explicit supported zone and target region."
  }
}

variable "permissions" {
  description = "Exact per-target permissions copied from Scenario validation, not guessed roles."
  type = map(object({
    target_id    = string
    actions      = optional(set(string), [])
    data_actions = optional(set(string), [])
  }))
  default = {}
  validation {
    condition = alltrue([for p in var.permissions :
      length(setunion(p.actions, p.data_actions)) > 0 &&
      alltrue([for a in setunion(p.actions, p.data_actions) :
        !strcontains(a, "*") && !startswith(lower(a), "microsoft.authorization/") &&
        !startswith(lower(a), "microsoft.chaos/")
      ])
    ])
    error_message = "Permissions must be explicit, non-empty and cannot grant role administration or fault-run access."
  }
}

variable "allow_destructive_configuration" {
  type        = bool
  description = "Opt in to defining destructive Actions; not execution authorization."
  default     = false
}

variable "agent_verified_target_ids" {
  type        = set(string)
  description = "Explicit VM IDs whose agent prerequisites, permissions, recovery and indirect workload impact have been independently verified; not execution authorization."
  default     = []
  validation {
    condition     = alltrue([for id in var.agent_verified_target_ids : can(regex("(?i)^/subscriptions/[^/*?#\\s]+/resourceGroups/[^/*?#\\s]+/providers/Microsoft\\.Compute/virtualMachines/[^/*?#\\s]+$", id))])
    error_message = "Agent verification must identify individual VMs without wildcards; VMSS, child resources and discovery scopes are not qualified here."
  }
}

variable "allow_high_pressure_configuration" {
  type        = bool
  description = "Opt in to configuring VM pressure above 50 percent within Action bounds; requires a reviewed progressive-pressure recovery plan and is not execution authorization."
  default     = false
}

variable "excluded_resource_ids" {
  type        = set(string)
  description = "Recovery, shared, monitoring and other forbidden targets."
  default     = []
}

variable "linked_database_allowlist" {
  type        = set(string)
  description = "Additional explicitly authorized affected linked databases for destructive Managed Redis unlink."
  default     = []
  validation {
    condition     = alltrue([for id in var.linked_database_allowlist : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cache/redisEnterprise/[^/]+/databases/[^/]+$", id))])
    error_message = "Supply explicit linked Managed Redis database resource IDs, not discovery scopes or clusters."
  }
}

variable "aks_extensions" {
  description = "References to operator-owned AKS extension installations; confirmation is not fault execution authorization."
  type = map(object({
    cluster_id             = string
    target_namespaces      = set(string)
    compatibility_verified = optional(bool, false)
    network_faults_enabled = optional(bool, false)
  }))
  default = {}
  validation {
    condition = alltrue([for extension in var.aks_extensions :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerService/managedClusters/[^/]+$", extension.cluster_id)) &&
      length(extension.target_namespaces) > 0 &&
      alltrue([for namespace in extension.target_namespaces :
        can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", namespace)) &&
        !startswith(namespace, "kube-") &&
        !contains(["default", "chaos-infrastructure", "chaos-validation"], namespace)
      ])
    ])
    error_message = "Reference explicit AKS cluster IDs and dedicated installed target namespaces, excluding default, system, extension and verification namespaces."
  }
}

variable "pod_scenarios" {
  description = "Bounded pod Actions referencing an existing extension, with AND-matched labels. No extension installation or fault runs are performed."
  type = map(object({
    description              = string
    extension_key            = string
    namespace                = string
    labels                   = map(string)
    fault                    = optional(string, "pod_delete")
    app_kind                 = optional(string, "deployment")
    duration_seconds         = optional(number, 60)
    pods_affected_percentage = optional(number, 10)
    chaos_interval_seconds   = optional(number, 61)
    target_container         = optional(string)
    container_tools_verified = optional(bool, false)
    cpu_cores                = optional(number)
    memory_megabytes         = optional(number)
    latency_milliseconds     = optional(number)
    packet_loss_percentage   = optional(number)
  }))
  default = {}
  validation {
    condition = alltrue([for s in var.pod_scenarios :
      contains(["pod_delete", "pod_cpu_hog", "pod_memory_hog", "pod_network_latency", "pod_network_loss"], s.fault) &&
      contains(["deployment", "statefulset"], s.app_kind) &&
      s.duration_seconds >= 1 && s.duration_seconds <= 60 && floor(s.duration_seconds) == s.duration_seconds &&
      s.pods_affected_percentage >= 1 && s.pods_affected_percentage <= 25 && floor(s.pods_affected_percentage) == s.pods_affected_percentage &&
      s.chaos_interval_seconds > s.duration_seconds && s.chaos_interval_seconds <= 3600 &&
      floor(s.chaos_interval_seconds) == s.chaos_interval_seconds
    ])
    error_message = "Select a supported pod fault/workload, a 1-60 second exposure and 1-25 percent of matched pods; deletion intervals must not repeat within the exposure."
  }
  validation {
    condition = alltrue([for s in var.pod_scenarios :
      can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", s.namespace)) &&
      !startswith(s.namespace, "kube-") &&
      !contains(["default", "chaos-infrastructure", "chaos-validation"], s.namespace) &&
      length(s.labels) >= 2 && lookup(s.labels, "chaos-canary", "") == "target" &&
      alltrue([for key, value in s.labels :
        can(regex("^([a-z0-9]([-a-z0-9.]*[a-z0-9])?/)?[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?$", key)) &&
        can(regex("^[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$", value))
      ])
    ])
    error_message = "Use a dedicated namespace and at least two exact labels including chaos-canary=target; empty values, wildcards and selector expressions are forbidden."
  }
  validation {
    condition = alltrue([for s in var.pod_scenarios :
      (!contains(["pod_cpu_hog", "pod_memory_hog"], s.fault) || (
        s.container_tools_verified && try(trimspace(s.target_container) != "", false)
      )) &&
      (s.fault != "pod_cpu_hog" || try(s.cpu_cores >= 1 && s.cpu_cores <= 2 && floor(s.cpu_cores) == s.cpu_cores, false)) &&
      (s.fault != "pod_memory_hog" || try(s.memory_megabytes >= 1 && s.memory_megabytes <= 128 && floor(s.memory_megabytes) == s.memory_megabytes, false)) &&
      (s.fault != "pod_network_latency" || try(s.latency_milliseconds >= 1 && s.latency_milliseconds <= 500 && floor(s.latency_milliseconds) == s.latency_milliseconds, false)) &&
      (s.fault != "pod_network_loss" || try(s.packet_loss_percentage >= 1 && s.packet_loss_percentage <= 10 && floor(s.packet_loss_percentage) == s.packet_loss_percentage, false))
    ])
    error_message = "Stress requires verified container tools and an explicit container; supply bounded integer CPU/memory/latency/loss parameters rather than inheriting unsafe fault defaults."
  }
}
