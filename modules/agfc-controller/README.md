# Official ALB controller (cluster stage)

Helm chart `alb-controller`, type `application`, official OCI repository
`oci://mcr.microsoft.com/application-lb/charts`, version/appVersion **1.13.0**.
The package was fetched in memory and verified against its OCI layer digest:
`sha256:e3d0ba8974c173e5fcfa7fafedaf6c4f8053d55c99711dba13ee5f645105b6d7`.
Terraform pins the chart version; this is not runtime image signature validation.
The chart owns namespaces, `alb-controller-sa`, cluster RBAC, CRDs and installation
hook Jobs. No duplicate handcrafted Kubernetes controller resources exist.
Those hooks run only when the controller is explicitly enabled.

Required inputs: `resource_group_name`, `location`, `oidc_issuer_url`,
`workload_identity_enabled=true`, `node_resource_group_id`,
`agfc_resource_group_id`, `association_subnet_id`, `association_id`.
Optional inputs: `identity_name`, `controller_namespace`, `tags`.

Owns only a controller UAMI, its federation, scoped role assignments and Helm
release. Federation subject is
`system:serviceaccount:<controller_namespace>:alb-controller-sa`, audience
`api://AzureADTokenExchange`. Helm receives the client ID; RBAC receives the
principal object ID. The existing AGFC association is a validated pass-through
contract, **not** a resource imported or created here.

Documented roles for BYO deployment:
| Role | Scope |
|---|---|
| Reader | Existing AKS node resource group |
| AppGw for Containers Configuration Manager | Existing AGFC resource group |
| Network Contributor | Exact delegated association subnet |

These are the verified documented built-in scopes, not subscription roles.
Network Contributor is broader than subnet join; a narrower custom role needs a
separate validated policy change. Deployment identity needs narrowly delegated
role-assignment write rights at these scopes plus identity/federation CRUD.
Reader on node RG and manager on AGFC RG are deliberately distinct.

Prerequisites: Linux supported AKS nodes, Azure CNI/Overlay, enabled OIDC and
Workload Identity, region/version compatibility, no existing ALB add-on/controller,
private operator API connectivity and permitted controller egress. Platform
provider registrations are a separately approved prerequisite, not an automatic
side effect. Role propagation is not guaranteed by `depends_on`; check readiness
and retry the approved deployment after propagation, not a fixed sleep.

**Blocked / not implemented:** region/cluster/network readiness and cloud
acceptance remain unverified; no Gateway/HTTPRoute/ApplicationLoadBalancer
workload is created and no frontend is discovered/assumed private. BYO Gateway
and TLS routing require a separately reviewed workload manifest after CRD
readiness. Do not use controller-managed creation to duplicate platform ownership.

Verified 2026-11-20:
- [Official Helm installation, chart and federation](https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-deploy-application-gateway-for-containers-alb-controller-helm)
- [BYO resource and RBAC requirements](https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-create-application-gateway-for-containers-byo-deployment)
