variable "verification" {
  description = "Explicitly opt-in cloud verification. No Jobs or fault actions by default."
  type = object({
    enabled            = optional(bool, false)
    run_jobs           = optional(bool, false)
    image              = optional(string)
    workload_client_id = optional(string)
    flows = optional(map(object({
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
    })), {})
  })
  default = {}
}

module "verification" {
  count              = var.verification.enabled ? 1 : 0
  source             = "../../modules/chaos-validation"
  image              = var.verification.image
  run_jobs           = var.verification.run_jobs
  flows              = var.verification.flows
  workload_client_id = var.verification.workload_client_id
}

output "verification_jobs" {
  description = "Cloud verification Jobs, empty unless specifically opted in."
  value       = var.verification.enabled ? module.verification[0].job_names : {}
}
