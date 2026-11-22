# Bounded cloud AKS availability verification

Apply this module only from the independently authenticated cluster stage. It prepares a restricted namespace, unprivileged service account and scripts ConfigMap. `run_jobs=false` by default. Deploying Jobs executes probes and requires explicit approval, even though it never starts a fault.

Supply a verified digest-pinned Python 3 image and distinct real application canary/control HTTPS URLs without credentials or query tokens. TLS verification stays enabled and redirects are rejected. The default 30 requests per path run concurrently and fit the default 900-second Job budget. Jobs have bounded requests, resources, deadline, retry count and retention. This namespace is not suitable for extension fault helper pods; do not weaken its security to install fault components.

The supplied script verifies **HTTPS availability only**. It does not prove database transactions, Redis consistency, AMQP acknowledgments, actual fault containment, or E-01/E-02 business invariants. Those remain Blocked until the real application contract, protocol-aware hooks and independent acknowledgment ledgers are supplied. Do not label direct probes as full business resilience.

Keep recovery/monitoring outside injected paths. Export evidence privately before Job TTL cleanup. Workload client identity input only annotates an explicitly supplied identity; create its federation and service data permissions separately. No host sockets, general Kubernetes credentials or fault-run permissions are granted.

## Optional phased availability measurements

Each flow may specify `phase` (`baseline`, `exposure`, `recovery`), `interval_seconds`, `minimum_observation_seconds`, `maximum_p95_seconds`, `maximum_p99_seconds` and `job_deadline_seconds`. Defaults preserve a finite burst probe with no agreed latency thresholds; this is not a complete baseline or resilience verdict. Deploy only one phase at a time, and explicitly authorize its traffic. The module does not start/cancel a fault or coordinate phase transitions.

For example, the following flow supports a 15-minute baseline with at least 1,000 requests per path. Values are proposals to replace with the real application contract:

```hcl
flows = {
  checkout-baseline = {
    canary_url                  = "https://canary.example.invalid/checkout"
    control_url                 = "https://control.example.invalid/checkout"
    phase                       = "baseline"
    operations                  = 1000
    minimum_success             = 0.999
    request_timeout             = 1
    interval_seconds            = 1
    minimum_observation_seconds = 900
    maximum_p95_seconds         = 0.5
    maximum_p99_seconds         = 1
    job_deadline_seconds        = 1200
  }
}
```

Requests are paced by their start time; control and canary use independent concurrent workers. Reports retain per-request timing/success samples, p95/p99, start timestamps and elapsed observation without URL values. A returned response that exceeds `request_timeout` is counted as a failure, not false success. urllib's socket timeout is not a hard end-to-end cancellation deadline; the finite Job deadline is the outer execution bound. Validate DNS/TLS and real timing in cloud AKS.

An exceeded success/latency threshold produces `Failed` (exit 1). Healthy but insufficient observation produces `Inconclusive` (exit 2), never `Passed`. `Passed` (exit 0) applies only to the supplied HTTPS availability thresholds. Job timeout, missing evidence, real fault containment, transactions, acknowledgment reconciliation and sustained window-by-window recovery require separate evaluation; an aggregate percentile does not prove every recovery window met SLO.

`job_deadline_seconds` is limited to 60-3600 seconds; validation requires the request/pacing budget plus 60 seconds of headroom to fit. `run_jobs=false` remains the default. No ingress controller or Argo CD is required for private AKS-reachable application URLs.
