resource "kubernetes_namespace" "argocd" {

  metadata {
    name = var.argocd_namespace
  }
}
resource "helm_release" "argocd" {
  name       = var.argocd_name
  repository = var.argocd_repository
  chart      = var.argocd_chart
  version    = var.argocd_version

  namespace = kubernetes_namespace.argocd.metadata[0].name

  # Enable upgrade functionality
  cleanup_on_fail = true
  atomic          = true
  timeout         = 900
  wait            = true

  values = [<<EOF
configs:
  params:
    server.insecure: false
server:
  extraArgs: []
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/azure-load-balancer-internal: "true"
repoServer:
  env:
    - name: ARGOCD_GIT_ATTEMPTS_COUNT
      value: "5"
dex:
  enabled: false
EOF
  ]

}