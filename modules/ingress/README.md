# Internal TLS ingress

Provider configuration is inherited; no random resource/provider is required.
Inputs retain RG/location/env prefix and pinned Helm chart settings. A
`tls_secret_name` in `namespace/name` form is mandatory. Provision that TLS secret
separately and verify its certificate/chain; private keys do not enter Terraform.
The release enforces internal Azure LoadBalancer, disables HTTP and redirects to
TLS. No public LB or plaintext override is exposed.

**Security exception / Blocked by default:** ingress-nginx retired in March
2026 and receives no new security fixes. The retained chart 4.0.18 has not been
certified against current AKS. Only explicitly approved nonproduction use may
set `allow_unsupported_nginx=true`; an upgrade/migration is a separate change.
This exception does not assert safety. Prefer `ingress_mode=none` until a supported
controller is selected. See the
[official retirement notice](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

Outputs: `release_name`, `namespace`. Mock tests check internal LB/TLS guards;
cloud deployment, private reachability and certificate validation are unverified.
