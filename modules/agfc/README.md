# Azure Application Gateway for Containers

This module owns only Azure AGFC, its association and frontend. No Kubernetes
provider, fabricated service account/RBAC, or DNS zone is created here. The
cluster-stage `agfc-controller` module owns the actual official controller.

Inputs retain `resource_group_name`, `location`, `env_prefix`, `vnet_id`,
`subnet_id`, names and tags. `vnet_id` is retained for caller compatibility.
`frontend_ip` is deprecated and must be null. `allow_public_frontend` defaults
false and must be explicitly true to deploy this module.

**Blocked for private ingress:** the service now supports private frontends via
private endpoints, but AzureRM **4.55.0** exposes no frontend type/private endpoint
configuration (resource API **2025-01-01**). This implementation creates the
default public frontend only, after explicit consent. Private DNS does not make
that frontend private. No fallback to a public frontend is silently performed.

Outputs: `agfc_id`, `agfc_name`, `frontend_id`, `frontend_name`,
`subnet_association_id`, `frontend_fqdn`. Deprecated `private_dns_zone_id` and
`private_dns_zone_name` return null.

The existing delegated subnet must have sufficient capacity (/24 minimum),
`Microsoft.ServiceNetworking/trafficControllers` delegation and verified
AKS connectivity. This module does not take ownership of the VNet/subnet.
Existing private DNS resources removed from this module need a reviewed
ownership migration; never blindly apply their proposed deletion.

## Migration review (no migration commands executed)

The removed `kubernetes-integration.tf` managed
`kubernetes_namespace.agfc`, `kubernetes_service_account.agfc`,
`kubernetes_cluster_role.agfc`, and `kubernetes_cluster_role_binding.agfc`.
These were incomplete handcrafted placeholders, not the official ALB controller.
The new official Helm release owns different namespace/SA/RBAC resources; there
is no valid automatic resource-address move into a Helm release. Inventory old
namespace contents and bindings, deploy/verify the approved official controller,
and explicitly review retirement of old resources in their original state.
Never delete a namespace containing unrelated workloads.

Also removed: `random_pet.agfc`, `azurerm_private_dns_zone.agfc`,
`azurerm_private_dns_zone_virtual_network_link.agfc`. DNS outputs are explicitly
deprecated nulls, not replacements. Preserve shared DNS using an approved
ownership transfer if required; review old-name Helm/DNS consumers before removal.
AGFC, association and frontend resource addresses and names remain unchanged.
Platform callers retain the original inputs; add `allow_public_frontend=true`
only with explicit approved public exposure and remove any non-null
`frontend_ip` input. None of these changes authorizes deployment or state removal.

Verified references (2026-11-20):
- [AzureRM 4.55.0 frontend schema](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.55.0/website/docs/r/application_load_balancer_frontend.html.markdown)
- [Current components and private frontends](https://learn.microsoft.com/azure/application-gateway/for-containers/application-gateway-for-containers-components)
