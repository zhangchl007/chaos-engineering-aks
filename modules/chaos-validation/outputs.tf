output "namespace" {
  description = "Dedicated verification namespace, not a fault-target authorization."
  value       = kubernetes_namespace_v1.test.metadata[0].name
}
output "job_names" {
  description = "Explicitly authorized Job names; empty when Jobs are disabled."
  value       = { for name, job in kubernetes_job_v1.test : name => job.metadata[0].name }
}
