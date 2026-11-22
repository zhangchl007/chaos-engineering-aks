mock_provider "kubernetes" {}
mock_provider "helm" {}

variables {
  resource_group_name     = "test-rg"
  location                = "westeurope"
  tls_secret_name         = "ingress-nginx/server-tls"
  allow_unsupported_nginx = true
}

run "internal_tls_values" {
  command = plan
  assert {
    condition     = yamldecode(helm_release.ingress.values[0]).controller.service.annotations["service.beta.kubernetes.io/azure-load-balancer-internal"] == "true"
    error_message = "Ingress must use an internal Azure load balancer."
  }
  assert {
    condition     = !yamldecode(helm_release.ingress.values[0]).controller.service.enableHttp && yamldecode(helm_release.ingress.values[0]).controller.extraArgs["default-ssl-certificate"] == var.tls_secret_name
    error_message = "Ingress must disable HTTP and use the explicitly referenced TLS secret."
  }
}

run "missing_tls_rejected" {
  command = plan
  variables {
    tls_secret_name = ""
  }
  expect_failures = [var.tls_secret_name]
}

run "retired_controller_requires_exception" {
  command = plan
  variables {
    allow_unsupported_nginx = false
  }
  expect_failures = [var.allow_unsupported_nginx]
}
