variable "namespace" {
  type        = string
  description = "Dedicated namespace, never default or a system namespace."
  default     = "chaos-validation"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace)) && !startswith(var.namespace, "kube-") && !contains(["default", "chaos-infrastructure"], var.namespace)
    error_message = "Use an explicit dedicated non-system namespace."
  }
}

variable "image" {
  type        = string
  description = "Approved Python 3 tool image pinned by digest."
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.image))
    error_message = "Supply a verified image digest."
  }
}

variable "run_jobs" {
  type        = bool
  description = "Explicit opt-in to execute verification Jobs; never starts faults."
  default     = false
}

variable "flows" {
  type = map(object({
    canary_url                  = string
    control_url                 = string
    operations                  = optional(number, 30)
    minimum_success             = optional(number, 0.99)
    request_timeout             = optional(number, 10)
    phase                       = optional(string, "baseline")
    interval_seconds            = optional(number, 0)
    minimum_observation_seconds = optional(number, 0)
    maximum_p95_seconds         = optional(number)
    maximum_p99_seconds         = optional(number)
    job_deadline_seconds        = optional(number, 900)
  }))
  description = "Approved real application HTTPS paths. These are availability probes, not database-integrity proof."
  default     = {}
  validation {
    condition = alltrue([for f in var.flows :
      can(regex("^https://[^/@?#[:space:]]+(/[^?#[:space:]]*)?$", f.canary_url)) &&
      can(regex("^https://[^/@?#[:space:]]+(/[^?#[:space:]]*)?$", f.control_url)) &&
      f.canary_url != f.control_url && f.operations >= 1 && f.operations <= 1000 && floor(f.operations) == f.operations &&
      f.minimum_success > 0 && f.minimum_success <= 1 && f.request_timeout > 0 && f.request_timeout <= 10 &&
      contains(["baseline", "exposure", "recovery"], f.phase) &&
      f.interval_seconds >= 0 && f.interval_seconds <= 60 &&
      f.minimum_observation_seconds >= 0 &&
      (f.operations - 1) * f.interval_seconds >= f.minimum_observation_seconds &&
      f.job_deadline_seconds >= 60 && f.job_deadline_seconds <= 3600 && floor(f.job_deadline_seconds) == f.job_deadline_seconds &&
      f.operations * max(f.request_timeout, f.interval_seconds) <= f.job_deadline_seconds - 60 &&
      (f.maximum_p95_seconds == null ? true : f.maximum_p95_seconds > 0 && f.maximum_p95_seconds <= f.request_timeout) &&
      (f.maximum_p99_seconds == null ? true : f.maximum_p99_seconds > 0 && f.maximum_p99_seconds <= f.request_timeout)
    ])
    error_message = "Use distinct token-free HTTPS paths and feasible interval/observation/latency limits; concurrent probes must fit a finite 60-3600 second Job budget with 60 seconds of headroom."
  }
  validation {
    condition     = alltrue([for name in keys(var.flows) : can(regex("^[a-z]([a-z0-9-]{0,48}[a-z0-9])?$", name))])
    error_message = "Flow keys must be short Kubernetes-safe names."
  }
  validation {
    condition     = length(distinct([for f in var.flows : f.phase])) <= 1
    error_message = "Deploy one measurement phase at a time; baseline, exposure and recovery must not run concurrently."
  }
}

variable "workload_client_id" {
  type        = string
  description = "Optional explicitly provisioned application verification identity client ID."
  default     = null
}
