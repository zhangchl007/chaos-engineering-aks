# Cluster integration stage

Independent root/state for already-existing AKS, **not** Azure infrastructure.
Terraform >=1.9 (local validation CLI 1.15.6); providers pinned AzureRM **4.55.0**,
Helm **2.17.0**, Kubernetes **2.38.0**. Child sources are `../../modules/...`.
No root/sharednetwork resources, local kubeconfig or admin credentials are used.

## State and authentication

Default backend is local: `../../local-state/dev/cluster.tfstate`, relative to
this stack, resolves to the repository's `local-state/dev/cluster.tfstate`.
Run `terraform -chdir=stacks/cluster init -input=false -lockfile=readonly` from the
repository root; no backend config or Storage account is required. The state is
separate from platform state and ignored by Git. Protect it and its backups, use
one operator/machine at a time, and select a distinct state path before the first
initialization of another environment.

Remote storage is optional: copy `azurerm-backend_override.tf.example` to
`backend_override.tf` in this stack, then supply approved storage RG/account/
container and a distinct cluster-stage Blob key through a private backend config.
The ignored override retains Entra authentication, not shared-key access.
Bootstrap storage independently only if needed; use Blob locking, private
connectivity and protected versioning/backups. Verify backend and provider
identity/tenant/subscription separately. Never reuse the platform state.
For an existing initialized backend/state, stop and review migration rather than
using `-reconfigure` or a new empty state to bypass it. No backend migration,
unlock or state removal is authorized by this configuration.

Required Terraform inputs:
`subscription_id`, `tenant_id`, `cluster_name`, `cluster_resource_group_name`.
AKS is found by name/RG, and node RG by the returned node resource group name.
The user kube-config endpoint/CA is read as data; only host and CA are used.
Both Kubernetes and Helm exec `kubelogin get-token` for Entra AKS server application
`6dae42f8-4368-4678-94ff-3960e28e3630`, tenant explicit, Azure public cloud.
No client certificate/key, password or token is copied into provider configuration.
AKS data source results still enter protected state.

Operators use `kubelogin_login_mode=azurecli` (default) with an approved Azure CLI
session; CI uses `workloadidentity` with independently configured
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE` and AzureRM
OIDC configuration. Terraform does not install tools or create token files.
Verify tenant, subscription, private API/DNS reachability and state access.
Deployment principal requires AKS Cluster User (user-credential lookup) and
approved Kubernetes/AKS Azure RBAC rights sufficient for chart-owned cluster
resources. No role assignment grants operator permissions automatically.

## Optional integration contracts (all disabled by default)

- `ingress_mode`: `none` (default), `nginx`, `agfc`.
- NGINX: `nginx_tls_secret_name=namespace/name` and explicit nonproduction
  `allow_unsupported_nginx=true` exception. Legacy controller is retired;
  compatibility and certificate trust must be verified separately.
- `enable_argocd=false`; enable only with `allow_legacy_argocd_chart=true`
  approved legacy-chart exception and precreated `argocd-server-tls`.
- AGFC: `agfc` object containing `resource_group_name`, `resource_group_id`,
  `association_id`, `association_subnet_id`, optional `identity_name`.
  Also explicitly confirm `workload_identity_enabled=true` after verifying the
  existing cluster; AzureRM's AKS data source does not export that setting.
  Passed association/subnet stay platform-owned. AKS must already enable OIDC
  and Workload Identity; controller gets the actual issuer from the AKS data.
  The module owns its UAMI/federation and documented narrowly scoped roles.
  Platform public frontend requires separate explicit
  `modules/agfc.allow_public_frontend=true` consent. No public endpoint is
  invented as a private alternative.

Outputs: `cluster_id`, nullable `ingress_release_name`, `argocd_namespace`,
`agfc_controller_identity_id`. Controller child additionally exposes
identity client/principal IDs, namespace, pass-through association ID.

## Validation / blockers

Static initialization/validation are not cloud acceptance. Configure and review a
private saved plan against the correct initialized backend before any authorized apply.
Run Terraform `fmt`, `validate` and mock tests separately from Azure tests; mock
`apply` runs create no cloud resources. No deployment or experiment is authorized
or started here. Default flags create no Kubernetes resources or Jobs; enabling
official charts can execute their installation hooks.

**Blocked** until verified: existing AKS region/network/versions/Entra RBAC,
identity role propagation, public frontend consent where applicable, approved
legacy security exceptions, independent TLS secrets/trust, private API/state
connectivity, and BYO Gateway/HTTPS workload manifests after CRD readiness.
RocketMQ/runtime artifact readiness is separately **Blocked**, not inferred
from VM provisioning. Results must distinguish static success, mock evidence and
unexecuted cloud checks.

Migration: review existing Helm/namespace/UAMI ownership and moved/import plans
before enabling this state. Do not duplicate an existing controller or ALB
add-on. Azure AGFC's old fabricated Kubernetes integration was removed; migrate
its state ownership explicitly rather than adopting duplicate resources.
