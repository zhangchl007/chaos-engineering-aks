
locals {
  ingress_name = "${var.env_prefix}-ingress"
}
resource "kubernetes_namespace" "ingress" {
  metadata {
    name = var.ingress_namespace
    labels = {
      name = var.ingress_namespace
    }
  }
}
resource "helm_release" "ingress" {
  name            = local.ingress_name
  repository      = var.ingress_repository
  chart           = var.ingress_chart
  version         = var.ingress_version
  namespace       = kubernetes_namespace.ingress.metadata[0].name
  atomic          = true
  cleanup_on_fail = true
  timeout         = 900
  values = [yamlencode({
    controller = {
      service = {
        annotations = {
          "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
        }
        enableHttp = false
      }
      extraArgs = {
        "default-ssl-certificate" = var.tls_secret_name
      }
      config = {
        "ssl-redirect"       = "true"
        "force-ssl-redirect" = "true"
      }
    }
  })]
}