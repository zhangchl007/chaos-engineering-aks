output "release_name" {
  description = "Internal TLS ingress Helm release name."
  value       = helm_release.ingress.name
}

output "namespace" {
  description = "Ingress controller namespace."
  value       = kubernetes_namespace.ingress.metadata[0].name
}
