# Event Hubs private fixture

AzureRM **4.55.0**, configured by the caller. Existing input/output names are
preserved. New inputs: `private_dns_zone_id` and optional
`workload_principal_ids` (stable keys to Entra principal **object** IDs).

The caller owns the VNet, `subnet_ids["privateendpoint-subnet"]`, shared
`privatelink.servicebus.windows.net` zone and its workload VNet links. This
module creates neither the DNS zone nor VNet links; Service Bus must receive
the **same** zone ID. The private endpoint includes a DNS zone group. There
is no node/delegated subnet fallback. Subnet ID validation cannot detect actual
delegation; confirm the supplied subnet is non-delegated before deployment.

`enable_private_endpoint = false` creates no endpoint and returns
`private_endpoint_id = null`; it does **not** enable public access. This is an
intentionally disconnected configuration unless separately owned private
connectivity exists. `private_dns_zone_id` may then be null and `subnet_ids` empty.
Standard/Premium only; public networking and local/SAS authentication are always
disabled, TLS is at least 1.2. Optional RBAC grants only Event Hub data sender
and receiver on this module's event hub, not namespace Contributor. Empty map
creates no assignments; send-only/receive-only identities should instead receive
their narrower role from the caller. Consumer group `$Default` can serve the
initial fixture; independent readers require explicitly configured groups later.

## Service case: Eventhub

From an authorized cloud AKS Job using workload identity, produce bounded events
with correlation IDs, receive/checkpoint, and verify acknowledged payloads and
sequence IDs before/during/after an independently approved disruption. Collect
latency, retries, lag and confirmed-event integrity. Creating these resources
is not proof of delivery, replay recovery or regional DR.

Native geo-disaster recovery/replication, secondary namespace, aliases, consumer
checkpoints, failover and DNS/client recovery require explicit later
configuration, service/SKU/region verification and execution approval. No
failover, restart, fault injection or restore is performed by this module.

## Migration and validation

Existing installations formerly owned `azurerm_private_dns_zone.eventhub`,
`azurerm_private_dns_zone_virtual_network_link.eventhub` and
`random_pet.eventhub`. Before applying this refactor, arrange a separately
approved ownership migration of DNS and its link to the shared-network owner.
Do not apply a plan that destroys the existing shared DNS zone or link.
The endpoint now uses index `[0]`; modern Terraform can infer the single-instance
to count migration, but inspect the actual saved plan before applying.
Event Hub uses AzureRM 4's `namespace_id`; namespace/public-auth changes must be
reviewed with all SAS clients migrated to Entra authentication first.

Mock/plan tests in `tests/` need Terraform >= 1.7 and the pinned provider.
The coordinator initializes and validates; no cloud validation has been
performed. **Blocked：云端收发、恢复及 DR 尚未执行，不能判为 Passed。**

Pinned official schema verification (2026-11-20):
[namespace](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/eventhub_namespace.html.markdown),
[event hub](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/eventhub.html.markdown),
[private endpoint](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/private_endpoint.html.markdown).
