# Legacy Azure Cache for Redis

Explicitly targets **`Microsoft.Cache/redis`**, not Managed Redis or the
Enterprise tier. No fault is started by this module.

## Existing reference (default)

Set **both** `existing_name` and `existing_resource_group_name`.
The module uses a GET-only `azapi_resource` data source at `2024-11-01` and a
resource-group data read. It neither imports nor changes the existing cache,
private endpoint, authentication, access policies or network lifecycle.
AzureRM's Redis data source also fetches keys, so it is deliberately not used.
Outputs `redis_id`, `redis_name`, `redis_hostname`, `redis_ssl_port` return real
Azure metadata. When no existing cache is selected and `enable_new = false`,
there are zero reads/resources and outputs are intentionally null.

The resource owner must verify TLS 1.2, disabled public/plaintext/key access,
private DNS and workload identity permissions before any business/fault test.
Reference mode is not a declaration that an existing cache is secure or authorized.
`access_policy_assignments` applies only to module-owned new fixtures.

## New fixture (explicit opt-in)

`enable_new = true` and `eligibility_confirmed = true` are both required,
along with `name`, `resource_group_name`, `location`, `subnet_id` and
`private_dns_zone_id`. Existing-reference inputs must be unset.
Creates a dedicated **Standard C1 / Redis 6** cache with TLS 1.2, disabled
public and plaintext access, disabled access-key authentication and Entra
authentication. It also creates a private endpoint; root owns subnet, DNS zone
and VNet links. No VNet injection or shared-cache takeover occurs.

Private endpoint group ID: **`redisCache`**.
Exact zone: **`privatelink.redis.cache.windows.net`**.
SDK endpoint: `<cache>.redis.cache.windows.net` using Azure's TLS port (normally
6380). Do not use Managed Redis's `privatelink.redis.azure.net`.

Supply `access_policy_assignments = { workload = "<principal-object-id>" }`
for fixture-only `azurerm_redis_cache_access_policy_assignment` resources.
The verified AzureRM 4.55.0 contract is `name`, `redis_cache_id`,
`access_policy_name = "Data Contributor"`, `object_id`, `object_id_alias`.
No subscription-wide RBAC is created. Entra federation and token refresh remain
caller-owned; an empty map leaves SDK testing **Blocked / 阻塞**.

No keys are output or explicitly retrieved by this module. **State warning:**
AzureRM's new-cache resource can retain service-generated keys in provider state
even when key authentication is disabled; safeguard backend/plan access. Existing
GET-only references avoid the key-returning AzureRM data source altogether.

## Eligibility and retirement (verified 2026-11-20)

The official **July 2026** update removed the planned October creation ban for
existing customers. In public cloud, a tenant qualifies if any subscription in
that tenant had a legacy cache before **2026-04-01**. New public-cloud customers
remain blocked. Government/China have no creation block before retirement.
Eligible Basic/Standard/Premium creation continues until **2028-09-30**.
The older October 2025 table on the same page is superseded by the July update.

`eligibility_confirmed` is an operator attestation, **not a bypass of policy or
proof of service availability**. If eligibility, SKU/region availability or
Azure policy cannot be confirmed, use only the existing-reference path and mark
fixture creation **Blocked / 阻塞**. Do not claim universal availability.
Basic/Standard/Premium retire **2028-09-30**; remaining caches are disabled from
October 2028. Enterprise/Enterprise Flash creation is blocked and those tiers
retire **2027-03-31**; this module does not create them.

## A/R scenarios

* **A / availability:** cloud AKS traffic baseline followed by a separately
  authorized, bounded **legacy Redis reboot**; measure request success, latency,
  client retry/reconnect and readiness. Do not apply that reboot action to
  `Microsoft.Cache/redisEnterprise`.
* **R / recovery:** verify acknowledged test keys, cache repopulation, reconnect
  and recovery time after the authorized reboot. This Standard fixture does not
  promise durable persistence or loss-free reboot.

Action model/version, exact target support, authorization, stopping thresholds,
recovery and cloud business evidence must be verified separately. A successful
Terraform plan or Chaos report is not a passed resilience test. Mocked tests
cover disabled/reference contracts and plaintext/TLS rejection only.

Official references:

* [Current creation eligibility](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-whats-new)
* [Retirement FAQ](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/retirement-faq)
* [Private DNS zones](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
* [Legacy API schema](https://learn.microsoft.com/en-us/azure/templates/microsoft.cache/2024-11-01/redis)
* [AzureRM 4.55.0 cache contract](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/redis_cache.html.markdown)
* [AzureRM 4.55.0 assignment contract](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/redis_cache_access_policy_assignment.html.markdown)
