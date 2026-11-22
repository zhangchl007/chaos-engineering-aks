# Azure PaaS chaos testing plan

**Status:** Draft for review; not execution authorization.  
**Documentation checked:** 2026-11-20.  
**Scope:** Azure Database for MySQL Flexible Server, Azure Database for PostgreSQL Flexible Server, Azure Cache for Redis, Azure Managed Redis, Azure Storage, and Azure Service Bus.

## 1. Recommendation and boundaries

Test the application flows that depend on PaaS, not just whether Azure reports a successful fault operation. Following the [Well-Architected reliability testing guidance][waf], validate bounded retries, deadlines, graceful degradation, recovery, and data integrity end to end.

Use three distinct mechanisms:

1. **Chaos Studio Workspaces / Scenarios:** supported service-direct Actions, after regional catalog, resource eligibility, identity, and API validation.
2. **Client-path simulation:** application test hooks or a protocol-aware fault proxy used only by selected test workloads in cloud AKS. This tests client resilience, not an actual Azure service outage.
3. **Service-native recovery drills:** backup restoration and regional promotion procedures not supplied by the selected Chaos Action.

Microsoft recommends Workspaces for new tests. Do not copy classic fault URNs, targets, or capabilities into Workspace Scenarios. Do not automatically fall back to classic when an Action is unavailable. See [Workspaces overview][workspaces] and [current Action catalog][catalog].

Proposed defaults:

- Dedicated non-production targets and synthetic data; no production or shared infrastructure.
- One service and one fault at a time; no overlapping runs on the same target.
- One labeled application canary initially, plus an unaffected control canary.
- Explicit target allowlist, namespace, workload labels, entity names, and destination endpoints.
- No modification of shared DNS, NSGs, private endpoints, or AKS node pools.
- No deployment, resource restart, scaling, flush, failover, or fault execution as part of this planning change.
- Approval of this document permits planning only. Deployment and execution require separate authorization.

## 2. Repository fit and unverified prerequisites

The following are source-code observations, **not an inventory of deployed Azure resources**:

| Area | Observation | Planning implication |
| --- | --- | --- |
| MySQL | [Module](../modules/mysql/main.tf) defines Flexible Server, HA, private networking, backups, and `geo_redundant_backup_enabled = false`; its root invocation is commented out in [main.tf](../main.tf). | Discover an approved target or separately provision a dedicated one. Confirm actual HA readiness. A geo-restore drill is not currently established by this configuration. |
| Redis | [Module](../modules/redis/main.tf) uses `Microsoft.Cache/redisEnterprise` with AzAPI; the root invocation is active. | Do not interpret the module name as proof of legacy Azure Cache for Redis. Verify SKU/product, HA, database name, persistence, and geo links before choosing Actions. |
| PostgreSQL, Storage, Service Bus | No matching resource modules were found in the inspected repository. | Obtain approved existing resource references or separately plan dedicated fixtures; do not silently extend shared resource ownership. |
| Terraform | [version.tf](../version.tf) pins AzureRM `3.115.0` and configures a local backend; the inspected lockfile includes AzAPI `2.7.0`. | Workspaces support in these provider versions is unverified. Any implementation needs schema verification, accurate CLI constraints, and an isolated state design. Provider upgrades and backend migrations remain separate approved changes. |
| AKS | The repository is intended for private AKS. | Run business validation in cloud AKS with working private DNS and private service access. Do not open public endpoints to make a test work. |

Before implementation, privately record each target's resource ID, tenant/subscription, region, SKU, networking mode, ownership, HA/replication state, approved recovery path, and cost ceiling. Keep real identifiers, credentials, and raw execution reports out of public documentation.

### Current service-direct support

The following identifiers and semantics are from the [Workspaces Action catalog][catalog]. Listed support is **not** proof of availability or eligibility in the user's subscription.

| Service / resource type | Action ID | Semantics and eligibility checks |
| --- | --- | --- |
| MySQL / `Microsoft.DBforMySQL/flexibleServers` | `microsoft-mysql-failover/1.0` | Cancelable; required `RestoreOnStop`. Confirm healthy eligible HA server. Restoring the original primary is an attempted operation, not a guaranteed rollback. |
| MySQL / same type | `microsoft-mysql-restart/1.0` | Discrete; one restart, no automatic undo. |
| PostgreSQL / `Microsoft.DBforPostgreSQL/flexibleServers` | `microsoft-azurepostgresql-failover/1.0` | Cancelable; required `FailoverMode`: `PlannedFailover` or `ForcedFailover`. `RestoreOnStop` and `SkipIneligibleServers` are optional. Read replicas and non-HA servers are ineligible. |
| Azure Cache for Redis / `Microsoft.Cache/redis` | `microsoft-azureclusteredcacheforredis-reboot/1.0` | Discrete; `RebootType`: `PrimaryNode`, `SecondaryNode`, or `AllNodes`. Use an explicit `ShardId` only for clustered caches. Not the Managed Redis reboot mechanism. |
| Managed Redis / `Microsoft.Cache/redisEnterprise` | `microsoft-managedredis-flushdatabase/1.0` | Discrete; `DatabaseName`. Destructive: a geo-linked flush can remove all data from ALL linked caches. |
| Managed Redis / same type | `microsoft-managedredis-forceunlink/1.0` | Discrete; `DatabaseName`, `LinkedDatabaseResourceIds`. Changes replication topology; no automatic re-link/undo. |
| Storage / `Microsoft.Storage/storageAccounts` | `microsoft-storageaccount-plannedfailover/1.0` | Discrete; account-wide, not container-scoped. Requires eligible geo-redundancy, completed initial synchronization, and both regions available. |
| Service Bus / `Microsoft.ServiceBus/namespaces` | `microsoft-servicebus-changequeuestate/1.0` | Cancelable; required `desiredState`: `Active`, `Disabled`, `SendDisabled`, or `ReceiveDisabled`; explicit `queues`. |
| Service Bus / same type | `microsoft-servicebus-changesubscriptionstate/1.0` | Discrete; required `topic`, `subscriptions`, `desiredState` (`Active` or `Disabled`). Explicit recovery is required. |
| Service Bus / same type | `microsoft-servicebus-changetopicstate/1.0` | Discrete; required `topics`, `desiredState` (`Active` or `Disabled`). Explicit recovery is required. |

Before generating resource configuration, retrieve the selected region's full Action schema, verify parameter shapes and duration limits, and pin the tested API version. The targeting documentation currently uses `2026-08-01-preview`; do not assume a preview schema is supported by the repository's providers.

No direct Managed Redis reboot Action is listed in this catalog. Connection interruption is not evidence of a real node failover. Likewise, queue disable is not a Service Bus regional outage, and an application network blackout does not physically disable an Azure region.

## 3. Workload and measurement design

### Cloud AKS test harness

- Run both the real application canary and an independent verification Job. A raw database ping or SDK probe alone cannot establish business resilience.
- Mount scripts through ConfigMaps; use validated, pinned tool images, resource requests/limits, execution deadlines, finite retries, and cleanup policies.
- Use least-privilege workload identities and secret references. Never mount a host Docker socket or grant general node privileges to business validation Jobs.
- Use application test hooks or dedicated protocol-aware proxies for simulations. Keep TLS validation enabled; do not introduce a plaintext network bypass.
- A proxy/hook must demonstrably affect the selected application path. Account for SQL/Redis/AMQP persistent connections, connection pools, and all relevant cluster endpoints.
- If in-cluster network injection is later selected, separately validate the AKS extension preview's private-cluster support and compatibility. Installing classic Chaos Mesh is not a universal prerequisite.
- Keep observability and recovery access outside the injected path. An independent recovery operator must be able to remove a fault even if the canary stops responding.

### Synthetic critical flows

| Service | User flow to exercise continuously | Integrity evidence |
| --- | --- | --- |
| MySQL / PostgreSQL | Create an order with an idempotency key; update inventory in the same transaction; read the acknowledged order. | Independent ledger of attempted/acknowledged IDs; unique business effects; transaction invariants; no half-completed order/inventory updates. |
| Both Redis products | Read an item through cache-aside; update the source of truth and invalidate/refill its cache entry. | Source-of-truth comparison, version/freshness checks, cache hit/miss rate, bounded backing-store reads. |
| Storage | Upload a blob with a unique operation ID; download and verify it; exercise application retries for interrupted transfer. | Hash, length, object/version metadata, acknowledgment ledger, and absence of duplicate logical uploads. |
| Service Bus | Publish an order event, consume with PeekLock, persist its business effect, and settle the message. | Producer acknowledgments, consumer attempt ledger, one committed business effect per ID, outstanding messages, DLQ reasons. |

These are proposed reference flows. Before execution, map them to actual application endpoints and business invariants. If only synthetic direct clients exist, report the result as client-library resilience, not full application validation.

For DB transactions whose commit response is lost, treat the outcome as **unknown** until reconciled by idempotency key. Do not blindly retry a non-idempotent write. For Service Bus, duplicate delivery is expected in some failure paths; duplicate business effects are not.

### Proposed acceptance targets for review

These are **project proposals, not Microsoft SLAs or universal service guarantees**.

| Dimension | Initial proposal |
| --- | --- |
| Baseline | 15 minutes; at least 1,000 relevant business operations; >=99.9% success and within the application's agreed latency SLO. Extend the window at low traffic rates. |
| Normal simulation exposure | 60 seconds initially; increase to 180 seconds only after a clean recovery. One application canary; one dependency. |
| End-to-end request deadline | 10 seconds for synchronous reference flows; replace with the actual business deadline before execution. No retry chain may exceed it. |
| Retries | Bounded exponential backoff with jitter; proposed maximum 3 retries total across all layers. Do not multiply SDK and application retries unintentionally. |
| Cache fallback | >=99% business success during cache-only loss, with p95 <=2x baseline, if the source of truth has verified fallback capacity. Otherwise require explicit, truthful bounded failure. |
| Dependency hard outage | A read/write requiring that unavailable dependency may fail. It must fail explicitly within the deadline or be durably queued under the agreed business contract; no false success. Unaffected control flow stays within baseline SLO. |
| Post-fault recovery | Return to the agreed SLO within 120 seconds after a short simulation is removed; then maintain it for 10 consecutive minutes. |
| DB HA failover | Proposed end-to-end RTO <=180 seconds from fault initiation and zero lost acknowledged committed transactions; confirm workload realism with replay backlog and connection-pool behavior. |
| Redis reconnection / warm-up | Proposed reconnection <=120 seconds after path restoration; hit ratio within 10 percentage points of baseline within 10 minutes. Recent cache writes can be lost; cache availability is not a durability guarantee. |
| Messaging recovery | Account for every acknowledged message; no duplicate committed business effect. Drain the bounded test backlog within 10 minutes after recovery, allowing the approved TTL/DLQ policy. |
| Storage planned failover | Separate maintenance window: reserve 3 hours for failover, verification, and failback. Proposed <=90 minutes per transition, to be confirmed for account size/features; no acknowledged object loss. |
| PITR / regional recovery | Agree RTO and RPO per target, backup/replication configuration, and data size before execution. No assumed zero RPO for asynchronous replication or backup restore. |

Measure separately: fault start, observed impact, alert, recovery decision, recovery action, dependency availability, application SLO recovery, and backlog completion. RTO for operator-driven DR includes detection and decision time, not just the Azure operation.

For simulations, also record time from fault removal to recovery. Do not use that shorter metric as a substitute for incident RTO.

## 4. Common cases applied to all six service families

Each case inherits the baseline, canary scope, measurement, and stop rules above. Re-run separately against each service's actual client protocol.

| ID / priority | Hypothesis and procedure | Pass evidence / recovery |
| --- | --- | --- |
| C-01 / P0 | **Connection blackout:** interrupt established and new connections from one canary to one dependency for 60 seconds. Leave the control client unaffected. | Deadlines honored; retry volume bounded; no false success or duplicate effects; control healthy. Remove the injection, recreate only affected test connections if necessary, and prove application recovery. |
| C-02 / P0 | **Latency degradation:** introduce +100 ms, then +500 ms in separate runs for 60 seconds each; do not change shared routes. | Pool/worker queues remain bounded; timeouts and circuit-breaker behavior match the agreed contract; p95/p99 and retry amplification captured. Remove delay and verify queues and pools normalize. |
| C-03 / P0 | **Ambiguous acknowledgment:** for a bounded set of synthetic operations, permit the request to reach the service but interrupt its response or settlement. Use a protocol-aware hook where required. | Reconcile unknown outcomes; one business effect per ID; no lost acknowledged durable work. Remove the hook and reconcile every selected ID. |
| C-04 / P1 | **Dependency DNS failure:** break resolution only for the test workload's dependency hostname for 60 seconds; test both reused and newly created connections. | Correct dependency-specific alerting, bounded failure, re-resolution and reconnect after removal. Existing sockets alone cannot establish successful DNS fault coverage. Restore only test-local DNS configuration. |
| C-05 / P1 | **Throttle/resource-limit response:** use bounded client hooks matching the actual SDK's error semantics. Use HTTP 429/503 only for applicable HTTP APIs; do not fabricate HTTP responses for SQL, Redis, or AMQP. | Retry only retryable errors; honor applicable server delay; bounded concurrency; no OOM or retry storm. Disable the hook, drain work, and verify recovery. This is simulation, not proof of real Azure throttling. |

Authentication refresh failures can be added later with a dedicated test identity. Do not revoke shared permissions or change production credentials to simulate them.

## 5. Service-specific test cases

### 5.1 Azure Database for MySQL Flexible Server

Prerequisites: approved Flexible Server, healthy eligible HA standby for M-01, tested backup availability for M-03, FQDN-based connection strings, and transaction/idempotency verification. Distinguish same-zone HA from zone-redundant HA. Neither a forced HA failover nor a restart is a complete region outage. See [MySQL HA][mysql-ha] and [backup/restore][mysql-backup].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| M-01 / P0 | As an order writer, I can continue after HA primary failover without losing committed orders. Use the MySQL failover Action under steady read/write load. | One dedicated HA server; one failover; proposed 5-minute Action duration subject to catalog validation. Select `RestoreOnStop=false` initially to avoid an unreviewed second transition. | Meet HA RTO; zero acknowledged transaction loss; pools reconnect via FQDN; inventory invariants hold. Verify the new primary and healthy HA. A planned return to the original primary is a separately authorized transition. |
| M-02 / P0 | As a user, I receive a bounded error or safe retry during a database restart, and service returns without manual application restart. Use the restart Action. | One dedicated server; one Discrete restart, not a timed 60-second outage. | Measure actual outage; no retry storm; no partial transactions or duplicate orders. Wait for Ready, rebuild stale connections, validate data and application SLO. |
| M-03 / P1 | As an operator, I can recover accidentally altered synthetic records to a chosen restore point. Use native PITR, not a Chaos failover Action. | One test fixture; record a checkpoint, alter only its data, restore to a new isolated server. | Restored pre-checkpoint records and invariants match; RTO/RPO measured; restored authentication/private networking verified. Do not overwrite or destroy the source. Cutover is optional and separately authorized. |

The MySQL HA documentation describes typical failovers of 60-120 seconds; this is not an end-to-end application guarantee. Geo-restore requires separately verified geo-redundant backups and is outside the default wave.

### 5.2 Azure Database for PostgreSQL Flexible Server

Prerequisites: healthy eligible HA primary/standby, supported compute tier, FQDN, valid connection-pool configuration, and backup readiness. Do not silently substitute read-replica promotion for HA failover. See [PostgreSQL HA][pg-ha] and [backup/restore][pg-backup].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| P-01 / P0 | As a transactional user, I retain acknowledged writes during a planned primary transition. Use `PlannedFailover` under load. | One dedicated HA server; one transition; proposed 5-minute duration subject to schema. Set `RestoreOnStop=false`; require eligibility rather than silently skipping. | HA RTO and integrity pass; pool reconnects; existing transactions are safely completed/retried/reconciled. Verify primary role and restored HA before another transition. |
| P-02 / P1 | As a user, I recover from an abrupt primary transition even with in-flight transactions. Use `ForcedFailover` only after P-01 recovers cleanly. | Same dedicated fixture; a new, separately authorized run. Capture WAL backlog and long-running transactions first. | Zero lost acknowledged committed writes for the healthy HA scenario; unknown commits reconciled; replay time measured. Wait for restored HA and application SLO; authorize failback separately. |
| P-03 / P1 | As an operator, I can restore corrupted synthetic data. Use native PITR to a new isolated server. | Chosen restore time within retained/available backups; no source replacement. | Validate restored records, schema, application compatibility, private networking, identities, RTO, and restore-point gap. Remove only approved temporary fixtures after evidence retention. |

WAL replay and workload can extend failover beyond typical timings. Same-zone HA cannot establish zone-loss resilience; the proposed HA RPO does not apply to asynchronous cross-region replica promotion.

### 5.3 Azure Cache for Redis

Assumption: "Azure Cache" means **Azure Cache for Redis**, not Azure CDN or another cache product. Confirm the product and SKU. Reboot coverage below applies to Basic/Standard/Premium `Microsoft.Cache/redis`; replica-specific tests require a replica. Enterprise is not this reboot path. See [cache administration][cache-admin].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| R-01 / P0 | As a cache-aside reader, I remain served during primary reboot using reconnect/fallback. Use `RebootType=PrimaryNode`. | One dedicated eligible cache; one reboot. For clustering, one explicit shard first; deliberately route selected keys there. | Cache fallback contract, bounded source load, topology refresh, and integrity pass. Verify cache availability and warm-up; no promise of cache-write durability. |
| R-02 / P1 | As a reader, I am not substantially disrupted by replica reboot. Use `SecondaryNode`. | Dedicated Standard/Premium target with a replica; one reboot; no simultaneous primary fault. | Control/application stay within agreed SLO; replica rejoins; redundancy restored. Basic is Blocked for this case, not a successful skip. |
| R-03 / P1 | As a user, I survive cold-cache misses without overwhelming the database. Expire/invalidate only approved synthetic keys through a test hook. | Bounded hot-key set; one workload; no whole-cache flush by default. | Bounded refill concurrency, correct values, warm-up target, and healthy source of truth. Disable the hook and rebuild only test keys. |

Exclude `AllNodes` from the initial wave. Reboot is not a cache flush and can still lose recent data. Existing Azure Cache for Redis deployments can be tested, but Microsoft recommends migration to Managed Redis; migration itself is not part of this plan.

### 5.4 Azure Managed Redis

Verify actual product/SKU even though the resource type is `redisEnterprise`. Determine whether data is disposable cache data or non-reconstructible sessions/state. Do not promise zero data loss from asynchronous Redis replication. See [Managed Redis architecture guidance][amr-waf] and [active geo-replication][amr-geo].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| A-01 / P0 | As a cache-aside user, I remain served when the Managed Redis client path disconnects. Apply C-01 with a cluster-aware client. | Selected canary and dedicated database path for 60 seconds; no service-node reboot claim. | Fallback, deadlines, topology refresh, warm-up, and source integrity pass. Remove the injection and prove real requests succeed. |
| A-02 / P1, destructive | As a user, I survive complete loss of reconstructible cache data. Use the flush database Action. | Dedicated disposable instance/database only; one flush. If geo-linked, ALL linked caches must be disposable and authorized, otherwise Blocked. | Approved cache fallback and source load limits pass; rebuild from source and verify warm-up. Cancellation cannot restore erased data. Never run against the only copy of durable business/session data. |
| A-03 / P1, regional | As a regional user, I redirect to a healthy geo-linked instance when my local cache path is unavailable. Isolate only the regional test clients, then execute the application's endpoint/identity redirection. | Dedicated eligible active geo-replication group; supported HA/SKUs/version/modules, matching configurations, and alternate private access verified. | Detection-to-recovery RTO, application-measured freshness/RPO, concurrent-write invariants, and healthy alternate region. Restore the path; verify convergence before traffic returns. This is regional client isolation, not an Azure region failure. |
| A-04 / P2, topology-changing | As an operator, I can remove an unavailable geo member without destabilizing healthy members. Use force-unlink with explicit linked database IDs. | Dedicated disposable group only; separate authorization for unlink and recovery lifecycle changes. | Healthy members remain usable; memory/replication behavior recorded. Follow the documented recovery procedure, including deletion/recreation of the affected test member where required; verify rejoin/convergence before returning traffic. |

Force-unlink is a recovery/topology action, not a substitute for inducing a real outage. Client isolation does not interrupt service-to-service replication; do not claim it proves metadata accumulation during a true regional loss.

The Geo Replication Healthy metric is a health indicator, not a numeric lag measurement. Measure freshness using application version markers. Managed Redis export/import recovery is not included by default: current guidance notes limitations with firewalled/private-link storage, and this plan must not weaken the network boundary to enable it.

### 5.5 Azure Storage account

Initial business scope is **Blob Storage**. Add explicit workload variants for Azure Files, ADLS Gen2, Queue, or Table if used; Blob results do not cover those protocols/semantics.

See [DR guidance][storage-dr], [planned failover behavior][storage-planned], and [initiation prerequisites][storage-start].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| S-01 / P0 | As an uploader, I either complete a verified upload or receive a truthful bounded failure during connection reset/transient errors. Apply C-01/C-03/C-05 to the Blob application path. | Dedicated container/prefix and selected canary; bounded operations and 60-second exposure. | Hash/length and acknowledgment ledger reconcile; no duplicate logical object or false completion. Remove injection, reconcile interrupted uploads, and validate reads/writes. |
| S-02 / P1 | As a read-only user, I can use the secondary endpoint when the primary client path is unavailable. Use application-controlled read fallback. | Dedicated RA-GRS/RA-GZRS account; selected reads only; confirm secondary service support and private access. | Reads respect agreed freshness; secondary is not used for writes; a not-yet-replicated object is handled correctly rather than declared lost. Restore primary path and verify application return. |
| S-03 / P1, account-wide DR | As an operator, I can move a geo-redundant account and restore service with no acknowledged object loss. Use the planned failover Action. | Dedicated account only, including every service/entity in it; synchronization complete; both regions healthy. Reserve the separate 3-hour window. | Measure end-to-end RTO; reconcile acknowledged objects and private DNS/access. After healthy verification, separately authorize planned failback and confirm original redundancy and replication. Stop cannot undo this Discrete transition. |
| S-04 / P1, recovery | As a user/operator, I can recover a deleted or overwritten synthetic blob using configured protection. Use version/soft-delete recovery, not regional failover. | Dedicated protected fixture; verify actual enabled protection and retention first. | Restore intended content/version and hash within agreed RTO; do not overwrite newer valid business data. Clean up only explicitly selected test objects. |

Do not fail over a Terraform backend account, backup repository, shared account, or account carrying recovery/observability dependencies. LRS/ZRS alone cannot support regional account failover.

Review the account's feature support matrix before S-03, including HNS, change feed/object replication, policies, and every storage service present. For Azure Files, stop all application/client share activity before failover and validate remount/reconnect afterward.

Planned failover requires both regions available, can take about an hour, and is **not** a test of recovery when the primary storage region is truly unavailable. Geo-redundancy is retained, but effective redundancy can change during the transition (for example GZRS to GRS) and return on planned failback. Verify actual state; do not let Terraform revert it mid-drill.

Unplanned account failover is excluded from default execution: it can lose unreplicated writes, remove geo-redundancy, and introduce inconsistencies. Add it only as a separately approved disposable-environment drill with an explicit data-loss budget and re-protection procedure.

### 5.6 Azure Service Bus

Use explicit dedicated queue/topic/subscription names and finite backlog/message TTL. Durable business events use PeekLock, not ReceiveAndDelete. See [message settlement/locks][sb-locks], [Geo-Replication][sb-georep], and [Geo-DR][sb-geodr].

| ID / priority | User story, hypothesis, and fault | Scope / exposure | Acceptance and recovery |
| --- | --- | --- | --- |
| B-01 / P0 | As a producer, I do not lose accepted business work when sends are disabled. Use queue state `SendDisabled`. | One dedicated queue, explicit `queues`; proposed 60-second duration subject to schema. | Sends fail truthfully or enter an approved durable outbox; existing messages remain consumable. Verify actual state recovery, explicitly restore the recorded state if needed, replay outbox, and reconcile IDs. |
| B-02 / P0 | As a consumer/operator, I recover from paused receives without backlog loss. Use `ReceiveDisabled`. | One dedicated queue for 60 seconds, with bounded publishers. | Backlog grows within its cap; alerts fire; send behavior verified; recovery drains without duplicate business effects. Restore recorded queue state and prove send/receive/settlement. |
| B-03 / P1 | As a subscriber, I recover after a topic or subscription is disabled. Execute separate runs of the topic and subscription state Actions. | Explicit topic/subscription list only; Discrete disable; planned 60-second hold managed by the operator, then explicit restoration. | Verify actual accepted/rejected work and affected subscriptions; no assumption that a disabled subscription accumulates backlog. Restore the original state even if the run is canceled; reconcile deliveries and DLQ. |
| B-04 / P0 | As an event processor, I avoid duplicate effects after connection/lock/settlement loss. Interrupt the selected consumer after business commit but before completion; also test handler delay beyond lock-renewal budget. | Bounded message cohort; canary consumer only; no global lock-setting change. | Redelivery handled idempotently; duplicate attempts allowed but only one effect; DLQ reasons reconcile. Remove fault, drain or explicitly dead-letter test messages, and verify lock renewal. |
| B-05 / P2, regional | As an operator, I recover messaging across regions with a known data contract. Prefer a native planned Geo-Replication promotion. | Dedicated eligible Premium namespace with synchronized secondary; current region support, identities, and private access verified. Not a queue-state Chaos Action. | Stable namespace hostname reconnects; planned promotion preserves acknowledged message data/state; end-to-end RTO and message ledger pass. Re-synchronize and authorize reverse promotion separately. |

Geo-Replication replicates metadata **and messages/state**. Synchronous and asynchronous modes have different latency, availability, and RPO behavior; forced promotion in asynchronous mode can lose data or duplicate effects and is excluded by default.

Geo-DR is a different, mutually exclusive configuration: it replicates **metadata only**, not queue/subscription/DLQ messages, and alias failover breaks the pairing. If the existing environment uses Geo-DR, define a separate outbox/replay and re-pairing drill rather than treating B-05 as applicable. Verify secondary RBAC and network configuration independently.

## 6. End-to-end extension after individual services pass

| ID / priority | Hypothesis | Controlled sequence and acceptance |
| --- | --- | --- |
| E-01 / P1 | Losing the cache does not overload the database or break the order flow. | Reuse the approved cache-only disruption while real cache-aside traffic runs. Do not also fault the DB. Assert backing-store headroom, business SLO, bounded refill, and correct records. |
| E-02 / P1 | A DB commit and outgoing business event remain reconcilable during messaging loss. | Reuse B-01 during the actual order-to-outbox-to-Service-Bus flow. Verify committed DB order, retained outbox event, one eventual consumer effect, and backlog drain. No atomicity claim across services without a proven application pattern. |

No multi-service overlapping fault is proposed initially. A later combined outage needs a new hypothesis, cumulative impact budget, and explicit authorization.

## 7. Safety, permissions, stopping, and restoration

### Pre-run gate

1. Confirm approved targets, affected users/data, time window, exposure limit, on-call operator, and recovery permissions.
2. Validate baseline, backup/replication health, private connectivity, remaining capacity, and absence of conflicting maintenance or experiments.
3. Review the resolved Workspace resource list and excluded list against the explicit allowlist. Dynamic discovery is not authorization. Require exact entity parameters; never leave them empty to imply all entities.
4. Verify Action/API/region/SKU eligibility and parameters. Missing support, unhealthy HA, or no matching target means Blocked.
5. Separate deployer, Workspace runtime identity, experiment operator, and application workload identities.
6. Derive custom least-privilege permissions from Scenario validation output. Assign only on approved targets; do not use subscription-level Contributor/Owner or automatically invoke permission-fixing operations.
7. Verify a tested cleanup/recovery procedure before fault start. Restore capacity includes the source of truth under cache misses and the consumer capacity required to drain messaging backlog.
8. Prevent Terraform/GitOps from correcting only the intentional temporary fault state during the authorized window; do not disable unrelated controllers or add broad permanent `ignore_changes`.

Use [resource targeting and validation][targeting] and [least-privilege role guidance][leastpriv]. Recommended catalog roles such as Contributor are references, not the default authorization policy.

### Proposed immediate stop/escalation conditions

- Any unapproved target or unaffected control flow is impacted.
- Any lost acknowledged durable record, duplicate business effect, broken transaction invariant, or unexpected corruption.
- Any unexplained success acknowledgment for failed/non-durable work.
- Control-flow success falls below 99% for 60 seconds, or p95 exceeds 2x baseline for 60 seconds.
- Retry calls exceed 3x baseline attempt rate for 30 seconds.
- Application/backing-store CPU or memory exceeds 80%, or connection use exceeds 80% of its verified limit, for 60 seconds.
- Test Service Bus backlog reaches 5,000 messages or 70% of approved entity capacity, whichever is reached first.
- Recovery/observability access is lost, or the approved window/budget is exceeded.

Tune thresholds before authorization. Dependency-specific expected failures are not automatically a reason to abort a hard-outage test; loss of containment, integrity, or recovery access is.

For Continuous/Cancelable faults, stop the run and remove the effect, then verify actual recovery. For Discrete or in-progress service-native transitions, stop further injection and escalate to the recovery runbook; do not assume cancellation reverses a restart, flush, unlink, or failover. Do not issue a competing failover while one is still in progress.

### Recovery completion gate

- Fault/proxy/hook removed; actual connectivity verified, not merely a successful control-plane response.
- Original entity states restored, or new primary state deliberately accepted.
- HA/replication healthy; cache warmed; messaging backlog and DLQ reconciled.
- Business SLO maintained for 10 minutes; all synthetic operation IDs accounted for.
- No unexpected drift; after approved recovery, inspect a correctly scoped Terraform plan privately. Do not apply it automatically to force the old topology.
- Clean up only owned test resources and assignments; retain required evidence privately. Never use `terraform destroy` as fault cancellation or business recovery.

## 8. Proposed execution waves, effort, and costs

| Wave | Work | Exit condition |
| --- | --- | --- |
| 0: Inventory and instrumentation | Privately verify service models/SKUs/networking; select actual business flows; agree SLO/RTO/RPO, quotas, and costs; prepare isolated fixtures and recovery runbooks. | Every selected case is executable or explicitly Blocked; permissions and containment demonstrated. |
| 1: Client resilience | C-01/C-02/C-03 per service, A-01, S-01, B-04, then C-04/C-05 where relevant. | Proven fault impact on real traffic; bounded failure and recovery; integrity checks pass. |
| 2: Single-service Actions | M-01/M-02, P-01 then P-02, R-01/R-02/R-03, B-01/B-02/B-03. | Actual HA/redundancy/entity recovery verified before each next run. |
| 3: Destructive and recovery drills | M-03/P-03/S-04; separately approved A-02, A-03/A-04, S-02/S-03, B-05. | RTO/RPO and restoration demonstrated, with explicit exclusions reported. |
| 4: Business-flow validation | E-01/E-02; repeat successful low-risk cases after fixes. | Complete evidence and review of remaining gaps; no unapproved multi-fault run. |

Suggested scheduling: budget 1-2 engineering days for inventory/measurement design, 2-3 days for the initial low-risk campaign, and separate maintenance windows for recovery/DR. These are planning allowances, not delivery guarantees; fixture provisioning and application changes can dominate.

Start with one run per low-risk case. After fixes, seek three consecutive clean runs for repeatable low-risk cases. Destructive/DR repetition is separately reviewed rather than automatically repeated three times.

Budget items: HA database primary/standby, separate legacy/Managed Redis fixtures, eligible geo-replicated Redis members, Service Bus Premium secondary capacity, geo-redundant storage, private networking, AKS test Jobs, Chaos Studio, and monitoring retention. Exact estimates depend on region, SKU, data size, and duration; no cost approval is assumed.

Repeat the agreed low-risk regression set after client/SDK/retry/network changes; schedule recovery/DR reviews at least quarterly or according to business risk. Coverage percentage is informational, not a global pass gate.

## 9. Evidence and result classification

For each run, capture privately:

- Case ID, hypothesis, authorization reference, exact resolved targets, API/Action versions, parameters, identities, and fixture configuration.
- Baseline, traffic volume, fault-impact evidence, unaffected-control results, timeline, and recovery actions.
- Business success/latency, retry amplification, pools/connections, Kubernetes events, service metrics/health, and alerts.
- Data/message reconciliation, hashes/invariants, lost/duplicate counts, RTO/RPO, backlog and warm-up results.
- Chaos report plus independent application evidence; recovery/drift checks; limitations and next action.

| Result | Meaning |
| --- | --- |
| Passed | Actual intended fault affected the approved traffic; business and integrity criteria met; restoration verified. |
| Failed | Fault ran but a required criterion failed, containment was violated, or recovery failed. |
| Inconclusive | Fault missed real traffic, evidence was insufficient, or the run was skipped without proving resilience. |
| Blocked | Prerequisites, support, permissions, targets, or authorization were missing; fault was not executed. |

Include a Chinese explanation of the evidence or blocker in the execution report, as required by the repository's delivery convention. A Chaos `Succeeded` is not a business Passed. Static Terraform validation, plan-only tests, and local probes are not cloud resilience validation.

**Current evidence:** Official documentation and repository configuration reviewed; no Azure inventory queried, no Terraform plan/apply run, and no cloud business or chaos test executed.

## 10. Review decisions before implementation

The draft proposes the following; change them during review:

1. Confirm the six product families, including Azure Cache for Redis, Flexible Servers, Blob-first Storage scope, and Service Bus messaging patterns.
2. Select dedicated targets or approve references to existing isolated test resources; confirm regions/SKUs/HA and private networking.
3. Name actual application flows and accept or replace the proposed SLO, RTO, RPO, stop thresholds, traffic volume, and durable queuing contract.
4. Approve Wave 1 as the first implementation scope. Keep all destructive/account-wide/regional cases opt-in.
5. Choose whether later recovery scope includes full cache flush, force-unlink/member recreation, Storage failover/failback, and Service Bus Premium Geo-Replication.
6. Set cost ceiling, maintenance windows, execution operator, and independently authorized recovery actions.

After review, the next deliverable is implementation-ready case/runbook configuration and a reviewed deployment plan, not immediate fault execution.

## Official references

- [Well-Architected reliability testing][waf]
- [Chaos Studio Workspaces overview][workspaces]
- [Workspaces supported resources and Action catalog][catalog]
- [Workspace resource targeting and validation][targeting]
- [Workspace least-privilege roles][leastpriv]
- [MySQL Flexible Server HA][mysql-ha]
- [MySQL Flexible Server backup and restore][mysql-backup]
- [PostgreSQL Flexible Server HA][pg-ha]
- [PostgreSQL Flexible Server backup and restore][pg-backup]
- [Azure Cache for Redis reboot/flush administration][cache-admin]
- [Azure Managed Redis architecture best practices][amr-waf]
- [Azure Managed Redis active geo-replication and force-unlink][amr-geo]
- [Storage DR planning and support restrictions][storage-dr]
- [Storage customer-managed planned failover][storage-planned]
- [Storage failover initiation prerequisites][storage-start]
- [Service Bus message transfer, locks, and settlement][sb-locks]
- [Service Bus Geo-Replication][sb-georep]
- [Service Bus Geo-Disaster Recovery][sb-geodr]

[waf]: https://learn.microsoft.com/en-us/azure/well-architected/reliability/reliability-test
[workspaces]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-overview
[catalog]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources
[targeting]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-resource-targeting
[leastpriv]: https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-least-privilege-roles
[mysql-ha]: https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-high-availability
[mysql-backup]: https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-backup-restore
[pg-ha]: https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability
[pg-backup]: https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore
[cache-admin]: https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-administration
[amr-waf]: https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-managed-redis
[amr-geo]: https://learn.microsoft.com/en-us/azure/redis/how-to-active-geo-replication
[storage-dr]: https://learn.microsoft.com/en-us/azure/storage/common/storage-disaster-recovery-guidance
[storage-planned]: https://learn.microsoft.com/en-us/azure/storage/common/storage-failover-customer-managed-planned
[storage-start]: https://learn.microsoft.com/en-us/azure/storage/common/storage-initiate-account-failover
[sb-locks]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/message-transfers-locks-settlement
[sb-georep]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-geo-replication
[sb-geodr]: https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-geo-dr
