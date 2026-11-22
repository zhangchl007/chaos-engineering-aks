output "release_name" {
  description = "Argo CD Helm release name."
  value       = helm_release.argocd.name
}

output "namespace" {
  description = "Argo CD namespace; credentials are intentionally not exposed."
  value       = kubernetes_namespace.argocd.metadata[0].name
}