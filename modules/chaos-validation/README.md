# Bounded cloud AKS availability and reference verification

Apply this module only from the independently authenticated cluster stage. It prepares a restricted namespace, unprivileged service account and scripts ConfigMap. `run_jobs=false` by default. Deploying Jobs executes probes and requires explicit approval, even though it never starts a fault.

Supply a verified digest-pinned Python 3 image and distinct real application canary/control HTTPS URLs without credentials or query tokens. TLS verification stays enabled and redirects are rejected. The default 30 requests per path run concurrently and fit the default 900-second Job budget. Jobs have bounded requests, resources, deadline, retry count and retention. This namespace is not suitable for extension fault helper pods; do not weaken its security to install fault components.

The default `probe.py` verifies **HTTPS availability only**. The optional [business runner](./business.py) adds bounded synthetic Blob and Service Bus reference flows with an independent operation ledger. Neither proves database transactions, cache fallback, actual fault containment, or E-01/E-02 business invariants. Real application contracts and protocol-specific implementation/qualification remain required. Do not label direct clients as full application resilience.

Keep recovery/monitoring outside injected paths. Export evidence privately before Job TTL cleanup. Workload client identity input only annotates an explicitly supplied identity; create its federation and service data permissions separately. No host sockets, general Kubernetes credentials or fault-run permissions are granted.

## Native Chaos Studio operations

The complete operator procedure for all 70 cases is in the [deployment and test runbook](../../docs/terraform-deployment-runbook.md#chaos-test-operations).
The project-local [native runner](./run_native_case.py), [configuration validator](./validate_native_targets.py),
[same-run observer](./observe_native_run.py) and [offline report summarizer](./summarize_native_runs.py) use Python's standard library.
The runner/validator require an explicitly checked Azure CLI subscription/tenant. Default execution is preflight only
(including native Validate); faults require `--execute` and separate authorization. Only nine bounded PaaS variants
are executable through this runner; forced failover, flush and VM/AKS actions are not added to its allowlist.
The observer only GETs an existing owned run and records recovery; it never replays Execute, cancels or changes a service.

Runtime inputs and retained journals default to `local-state/dev/chaos-testing/`, under the repository's ignored private storage.
Use `--config-dir` for a separately approved cohort/environment. An existing journal prevents replay and is never overwritten
to start another run. Public [twelve-scenario input guidance](../../environments/native-chaos.example.tfvars.json)
contains placeholders and keeps destructive configuration off; never replace populated state inputs with an empty onboarding map.
Historical session-only test helpers and inputs have been retained in the project-private `history/` directory for traceability,
not as active installation, permission or cleanup entry points. No active native tool depends on a Copilot session directory.
These scripts are operator tools, not additions to the Terraform Job command or automatic deployment hooks.

```bash
python3 modules/chaos-validation/run_native_case.py --check-inputs
python3 modules/chaos-validation/summarize_native_runs.py --markdown
python3 -m unittest discover -s modules/chaos-validation/tests -p 'test_native.py'
```

All three commands above are offline. A sanitized historical summary does not establish current cloud health,
actual Redis node/replication effects or full business acceptance.

## Optional phased availability measurements

Each flow may specify `phase` (`baseline`, `exposure`, `recovery`), `interval_seconds`, `minimum_observation_seconds`, `maximum_p95_seconds`, `maximum_p99_seconds`, `job_deadline_seconds` and `stream_evidence`. Defaults preserve a finite burst probe with no agreed latency thresholds and one final report; this is not a complete baseline or resilience verdict. Deploy only one phase at a time, and explicitly authorize its traffic. The module does not start/cancel a fault or coordinate phase transitions.

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

## Live evidence and independent stop signal

Set `stream_evidence=true` on an explicitly approved flow to emit flushed JSON Lines: `observation_started`, one `measurement` per completed request, and `observation_completed` retaining the existing aggregate report. Version 1 records share a random observation ID and phase; each stream has a zero-based sequence, elapsed start time, latency and success. No URLs or response bodies are emitted. Concurrent workers serialize their writes so records cannot interleave. Streaming is off by default to preserve single-report consumers.

The ConfigMap packages `stop.py`, but the declared Job still invokes only `probe.py`. Run the evaluator as an independent process on an approved recovery runner or separately approved monitoring workload, outside the injected path. It reads evidence on stdin and policy JSON from `STOP_POLICY`; it has no Azure/Kubernetes client, fault-start/cancel action, or recovery permission. Packaging it does not deploy or execute a monitor.

For an **already authorized** streaming Job, this is an illustrative read-only log follower, not a deployment/run command:

```bash
set -o pipefail
kubectl logs --follow --namespace chaos-validation \
  job/verify-checkout-exposure --container verification |
  STOP_POLICY='{"streams":["control"],"window_operations":60,"minimum_success":0.99,"maximum_silence_seconds":15,"maximum_monitor_seconds":240}' \
  python3 modules/chaos-validation/stop.py
```

Replace the Job, cadence, windows, thresholds and budgets with the approved contract. At one sample per second, 60 samples approximate a one-minute window; this is a **sample-count** window, not a time-window SLO proof. Require enough samples to fill the window. Optional `maximum_p95_seconds`, `maximum_p99_seconds` and `stop_after_consecutive_failures` support latency or early-failure thresholds. Monitor `control` by default; add `canary` only when its expected exposure behavior should trigger a stop.

Start monitoring at the beginning of a known observation and preserve the start/completion records. A complete healthy policy returns `Passed`/0 **for the stop signal only**, even when expected canary failures make the probe's aggregate result `Failed`. A monitored threshold breach or exhausted monitoring budget returns `Failed`/1. Missing start/samples/completion, insufficient observation or silence on any monitored stream returns `Inconclusive`/2. Invalid policy/JSON/identity or oversized records returns `Blocked`/3. Every non-Passed result recommends operator stop/escalation; the evaluator never performs it.

Silence uses local receipt time and cannot certify the freshness of replayed/delayed logs. A saved-log replay validates recorded evidence, not a live safety path. Qualify log transport, freshness, operator notification and monitor-failure recovery in cloud AKS before a fault. CPU/memory/backlog, acknowledged writes and integrity stop conditions still need independent business/service observers. The availability evaluator does not establish complete I2 or business resilience.

## Optional reference workloads and durable reconciliation

[business.py](./business.py) supports Blob upload/read/hash checks (`S-01`) and Service Bus queue publish/PeekLock/unique-effect/settlement checks (`B-01`, `B-02`, `B-04`). It does not inject any fault, change an entity state, create queues/containers, or delete test data. `B-04` still needs an approved settlement-loss hook or a real qualified disruption. SQL, Redis, Event Hubs, Cosmos, RocketMQ and actual cross-service application clients are not implemented by this batch.

The existing Terraform Job **still runs only `probe.py`**. Packaging the new scripts changes no runtime command and does not launch reference workloads or an independent monitor. Deploying any ConfigMap/Job remains a separate operation; day-one implementation performs no Terraform apply or deployed infrastructure/Chaos change.

The reference path requires Python 3.10+ and the hash-locked SDKs in [requirements-business.txt](./requirements-business.txt), resolved from [requirements-business.in](./requirements-business.in). Existing availability/stop scripts remain standard-library-only. Build/verify an approved digest-pinned tool image separately; never install unpinned packages at Job startup. CI includes offline SDK binding checks and never logs in to Azure or launches traffic.

Copy [campaign.example.json](./campaign.example.json) and [business.example.json](./business.example.json) into a private directory and replace all placeholders. Never add credentials or private manifests to source control. Use a fresh random 32-hex run ID for each new phase/cohort; never restart a killed writer with the same run ID.

Default commands are offline/read-only:

```bash
python3 modules/chaos-validation/business.py --config /private/reference-flow.json
python3 modules/chaos-validation/campaign.py --manifest /private/campaign.json
```

The first checks configuration only without creating clients/ledgers or requesting tokens. The second reports missing prerequisites and **never certifies a case**. Its case registry recognizes all 70 IDs in the [canonical catalog](../../docs/chaos-test-and-coverage-plan.md), including unselected/future cases, without granting readiness or execution. Recognition does not implement a fault or a protocol adapter. Qualification flags must represent actual evidence; setting them to true is not live validation. They do not replace current Azure provisioning/permissions/target checks, measured baseline, notification rehearsal or operator review. The example intentionally cannot authorize traffic.

### Before authorized traffic

- Use exact owned dev/test resource IDs and matching token-free service endpoints. Control must use a different account/namespace, not merely another entity on the faulted service.
- Provision only explicitly approved dedicated `chaos-` containers/queues and least-privilege data access separately. No management keys, pasted passwords, shared entities or permission auto-repair are used.
- Supply an independently provisioned AKS workload identity through the projected federation token; the runner uses `WorkloadIdentityCredential`, not personal CLI tokens or client secrets.
- Mount a **qualified durable writable ledger volume** at the manifest's exact path. `emptyDir`, container-local files and unverified network filesystems do not establish durability. SQLite uses WAL, FULL synchronous commits and a private database file; validate the volume's fsync/locking/crash behavior and independent reader access in cloud AKS. Keep storage, writer/reader and recovery access outside the actual fault selection, including node/zone cases.
- Establish a finite Job/process supervisor deadline, approved maintenance/cost window and independently tested stop/recovery path. SDK socket/operation timeouts and checks between calls are not hard process cancellation.

For a **separately authorized and ready** workload only:

```bash
timeout --signal=TERM --kill-after=5s 3600s \
  env ALLOW_REFERENCE_TRAFFIC=true \
  python3 /scripts/business.py --execute \
    --config /private/reference-flow.json \
    --manifest /private/campaign.json \
    --ledger /evidence/operations.sqlite
```

Run this inside the approved tool workload, not as a local substitute for cloud testing. The reference writer commits intent before attempting the service call, records observed acknowledgments or unknown outcomes without blind write retries, and persists expected payload hashes. Blob reads are bounded. Service Bus commits one synthetic effect per operation ID **before** completing the message; redelivery repeats are recorded without duplicate effects. Unrelated messages are abandoned and the verifier stops instead of acknowledging them. A conflicting hash fails integrity; missing effects, incomplete cohorts, unconfirmed settlement or interrupted ledger writes cannot pass.

Control/canary producers run concurrently. Flushed measurement records are compatible with `stop.py`; they measure **producer acknowledgment latency**, not full end-to-end business latency. The final ledger result separately checks effects/settlement. A control-only availability signal may be healthy while business reconciliation fails; independently observe both outputs and integrity. CPU/resource/retry/backlog observers and qualified notification/monitor deployment remain necessary.

### Recovery of existing operations

The ledger records hashes and synthetic effects, not a real application's durable outbox. Do not claim the intent table can replay lost business payloads. Unknown write outcomes are not accepted writes, and discovering their effect later does not fabricate a timely acknowledgment.

After service recovery and appropriate verification/settlement authorization, `--verify-existing` verifies the **original cohort without resending**:

```bash
env ALLOW_REFERENCE_TRAFFIC=true python3 /scripts/business.py \
  --verify-existing --config /private/reference-flow.json \
  --manifest /private/campaign.json --ledger /evidence/operations.sqlite
```

This may read blobs and receive/complete only the known test-message cohort; it is not a read-only cloud operation. The same manifest/identity/window gates apply. An incomplete interrupted producer is not automatically resumed or declared finished.

For **local read-only reconciliation with no service calls**, use:

```bash
python3 modules/chaos-validation/business.py --reconcile \
  --config /private/reference-flow.json --ledger /private/retained/operations.sqlite
```

`Passed`/0 is limited to the declared synthetic producer acceptance and verified effects. `Failed`/1 means a content conflict or unmet request threshold. `Inconclusive`/2 means unproven operations/effects/settlement or an interrupted runtime. `Blocked`/3 means prerequisites/configuration/dependencies/storage are unavailable before traffic. A complete case still needs real impact/containment, application contracts, recovery/RTO/RPO and drift evidence.

### Recorded sustained recovery windows

```bash
python3 modules/chaos-validation/campaign.py \
  --manifest /private/campaign.json --recovery-jsonl /private/recovery.jsonl
```

The checker validates one identified complete recovery observation and each configured window from observation start, requiring per-stream minimum samples, success and p95/deadline thresholds. A healthy aggregate with missing windows is `Inconclusive`; duplicate/mixed/malformed evidence is `Blocked`. Passing covers only those recorded availability windows, not live evidence freshness, later regressions, incident RTO, business integrity or case certification. Retain private ledger/WAL evidence safely before TTL cleanup; do not destroy targets or a backend as cleanup.
