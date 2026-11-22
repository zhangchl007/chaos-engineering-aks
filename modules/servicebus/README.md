# Service Bus private fixture

Caller-configured AzureRM **4.55.0**; object defaults need Terraform >= 1.3.

Required inputs: `name` (caller-generated globally unique namespace name),
`resource_group_name`, `location`, `private_dns_zone_id`, and either `subnet_id`
or `subnet_ids["privateendpoint-subnet"]`. If both subnet contracts are passed,
they must match. Shared network ownership stays outside this module.
The zone must be `privatelink.servicebus.windows.net`, **the same zone ID
passed to Event Hubs**, with VNet links already configured externally. Neither
module creates its own duplicate zone. Confirm the endpoint subnet is actually
non-delegated; resource ID validation alone cannot establish this.

Defaults: `sku = "Premium"` (private-only; other SKUs rejected), `capacity = 1`,
one messaging partition, `tags = {}`, `queues = { test-queue = {} }`,
`topics = {}`, `subscriptions = {}`. Queue settings are `max_delivery_count`
(10), `lock_duration` (`PT1M`), `default_message_ttl` (`P1D`).
Topics support `default_message_ttl` (`P1D`).
Subscriptions require `name`, `topic_key` referencing an explicitly declared
topic, and optional `max_delivery_count` (10). Azure validates duration limits
and globally unique namespace names. Premium regional availability and capacity
must be checked before approval.

Outputs: `namespace_id`, `queue_names` and `topic_names` (maps keyed by inputs),
`private_endpoint_id`. A private DNS zone group is attached to the endpoint.
Public access and SAS/local authentication are disabled; minimum TLS is 1.2.
Optional `workload_principal_ids` maps stable keys to Entra principal **object**
IDs; each gets data sender and receiver at each module-owned queue/topic scope,
not namespace-wide Contributor. Empty map creates no assignments. For identities
needing only send or receive, manage the narrower data role outside this module.

## Service case: S (Service Bus)

An authorized cloud AKS workload-identity Job sends correlated test messages,
receives under peek-lock, completes acknowledgements, checks retries, duplicate
handling and dead-letter counts, and verifies acknowledged-message integrity.
Measure latency and recovery against a baseline through a separately approved
disruption. Topic fan-out requires explicit topic/subscription inputs; no
subscriptions or native DR topology are silently created.

Native geo-disaster recovery/geo-replication, paired namespace, alias/client
routing, replicated data guarantees, failover and failback require **later
explicit configuration and approval** after checking actual SKU/region support.
Queue creation is not regional DR coverage. No automated fault, purge,
failover, restore or protection operation is configured.

## Validation / blockers

`tests/` contains Terraform >= 1.7 mock/plan tests, not cloud apply tests.
The coordinator initializes/validates the pinned provider; this module does not
modify root/provider/backend/network configuration.
**Blocked：尚无云端收发、故障或恢复证据；原生 DR 未配置，不判为 Passed。**

Pinned official schemas checked 2026-11-20:
[namespace](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/servicebus_namespace.html.markdown),
[queue](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/servicebus_queue.html.markdown),
[topic](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/servicebus_topic.html.markdown),
[subscription](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/servicebus_subscription.html.markdown).
