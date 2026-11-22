terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

resource "kubernetes_namespace_v1" "test" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of"          = "chaos-validation"
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

resource "kubernetes_service_account_v1" "test" {
  metadata {
    name        = "verification"
    namespace   = kubernetes_namespace_v1.test.metadata[0].name
    annotations = var.workload_client_id == null ? {} : { "azure.workload.identity/client-id" = var.workload_client_id }
  }
  automount_service_account_token = false
}

resource "kubernetes_config_map_v1" "scripts" {
  metadata {
    name      = "verification"
    namespace = kubernetes_namespace_v1.test.metadata[0].name
  }
  data = { "probe.py" = file("${path.module}/probe.py") }
}

resource "kubernetes_job_v1" "test" {
  for_each = var.run_jobs ? var.flows : {}
  metadata {
    name      = "verify-${each.key}"
    namespace = kubernetes_namespace_v1.test.metadata[0].name
    labels    = { "chaos-canary" = "verification" }
  }
  spec {
    active_deadline_seconds    = each.value.job_deadline_seconds
    backoff_limit              = 0
    ttl_seconds_after_finished = 3600
    template {
      metadata {
        labels = {
          "chaos-canary"                = "verification"
          "azure.workload.identity/use" = var.workload_client_id == null ? "false" : "true"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.test.metadata[0].name
        restart_policy       = "Never"
        node_selector        = { "kubernetes.io/os" = "linux" }
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          fs_group        = 10001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name    = "verification"
          image   = var.image
          command = ["python3", "/scripts/probe.py"]
          env {
            name  = "FLOW"
            value = jsonencode(each.value)
          }
          env {
            name  = "PYTHONDONTWRITEBYTECODE"
            value = "1"
          }
          resources {
            requests = { cpu = "100m", memory = "64Mi" }
            limits   = { cpu = "500m", memory = "128Mi" }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }
        }
        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map_v1.scripts.metadata[0].name
          }
        }
      }
    }
  }
  wait_for_completion = true
  timeouts { create = "${ceil(each.value.job_deadline_seconds / 60) + 5}m" }
}
