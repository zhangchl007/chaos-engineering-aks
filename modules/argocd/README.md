# Internal Argo CD

Providers are inherited from `stacks/cluster`. `kubeconfig_path` is a deprecated,
ignored compatibility input; no local file or admin credentials are read.
Release/name/namespace/chart inputs are preserved. The service is an internal
Azure LoadBalancer. Server TLS remains enabled, `--insecure` and repo-server
plaintext overrides are removed; upgrades do not use `force_update`.

Precreate `argocd-server-tls` in the Argo CD namespace using an independently
managed secret/certificate workflow. The retained chart recognizes that standard
secret; `tls_secret_name` validates its fixed name. Check certificate trust and
expiry after deployment. If absent, Argo CD can generate a self-signed certificate:
**that is not a trusted-TLS acceptance result**. No secret material or initial
admin password is output. HTTPS client validation must not use `--insecure`.

**Blocked by default:** the retained 5.24.1 chart is legacy and requires the
explicit `allow_legacy_chart=true` nonproduction security exception after review.
A supported chart migration is separate; compatibility/security is not claimed.
Chart-owned RBAC is cluster-wide and must be approved for the dedicated cluster.
No Applications, auto-sync workloads or validation Jobs are created here.

Outputs: `release_name`, `namespace`. Cloud TLS, RBAC and application readiness
are unverified.
