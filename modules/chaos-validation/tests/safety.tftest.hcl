mock_provider "kubernetes" {}

variables {
  image = "example.invalid/tools@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

run "preparation_does_not_run_jobs" {
  command = plan
  variables {
    flows = {
      application = { canary_url = "https://canary.invalid", control_url = "https://control.invalid" }
    }
  }
  assert {
    condition     = length(kubernetes_job_v1.test) == 0
    error_message = "Preparing verification must not execute Jobs."
  }
  assert {
    condition = alltrue([
      for script in ["stop.py", "ledger.py", "business.py", "campaign.py"] :
      kubernetes_config_map_v1.scripts.data[script] == file(script)
    ])
    error_message = "Independent safety/business scripts must be packaged without executing Jobs or traffic."
  }
}

run "authorized_job_meets_restricted_profile" {
  command = plan
  variables {
    run_jobs = true
    flows = {
      application = { canary_url = "https://canary.invalid", control_url = "https://control.invalid" }
    }
  }
  assert {
    condition = (
      kubernetes_job_v1.test["application"].spec[0].template[0].spec[0].security_context[0].seccomp_profile[0].type == "RuntimeDefault" &&
      kubernetes_job_v1.test["application"].spec[0].template[0].spec[0].node_selector["kubernetes.io/os"] == "linux" &&
      !kubernetes_job_v1.test["application"].spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation
      && kubernetes_job_v1.test["application"].spec[0].template[0].spec[0].container[0].command == tolist(["python3", "/scripts/probe.py"])
    )
    error_message = "Explicitly enabled Jobs must satisfy restricted Pod admission and target Linux."
  }
}

run "system_namespace_rejected" {
  command = plan
  variables { namespace = "kube-public" }
  expect_failures = [var.namespace]
}

run "mutable_image_rejected" {
  command = plan
  variables { image = "example.invalid/tools:latest" }
  expect_failures = [var.image]
}

run "same_control_canary_rejected" {
  command = plan
  variables {
    flows = { application = { canary_url = "https://same.invalid", control_url = "https://same.invalid" } }
  }
  expect_failures = [var.flows]
}

run "deadline_overrun_rejected" {
  command = plan
  variables {
    flows = { application = { canary_url = "https://canary.invalid", control_url = "https://control.invalid", operations = 1000, request_timeout = 10 } }
  }
  expect_failures = [var.flows]
}

run "finite_baseline_window" {
  command = plan
  variables {
    run_jobs = true
    flows = {
      application = {
        canary_url                  = "https://canary.invalid"
        control_url                 = "https://control.invalid"
        phase                       = "baseline"
        operations                  = 1000
        request_timeout             = 1
        interval_seconds            = 1
        minimum_observation_seconds = 900
        maximum_p95_seconds         = 0.5
        maximum_p99_seconds         = 1
        job_deadline_seconds        = 1200
        stream_evidence             = true
      }
    }
  }
  assert {
    condition     = kubernetes_job_v1.test["application"].spec[0].active_deadline_seconds == 1200
    error_message = "A baseline must have a feasible, explicitly bounded observation deadline."
  }
  assert {
    condition     = jsondecode(kubernetes_job_v1.test["application"].spec[0].template[0].spec[0].container[0].env[0].value).stream_evidence
    error_message = "Explicit streaming must reach the probe through its typed flow configuration."
  }
}

run "too_short_observation_schedule_rejected" {
  command = plan
  variables {
    flows = {
      application = {
        canary_url                  = "https://canary.invalid"
        control_url                 = "https://control.invalid"
        phase                       = "recovery"
        operations                  = 30
        interval_seconds            = 1
        minimum_observation_seconds = 600
      }
    }
  }
  expect_failures = [var.flows]
}

run "mixed_phases_rejected" {
  command = plan
  variables {
    flows = {
      baseline = { canary_url = "https://canary.invalid", control_url = "https://control.invalid", phase = "baseline" }
      exposure = { canary_url = "https://canary.invalid", control_url = "https://control.invalid", phase = "exposure" }
    }
  }
  expect_failures = [var.flows]
}
