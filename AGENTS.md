# AGENTS.md

## Repo Shape
- This is an Argo CD GitOps repo for a k3s homelab; there are no package scripts, app tests, or language build steps at the root.
- Argo CD tracks `main` from `https://github.com/kacperjarocki/homelab.git`. The root Application (`argocd/bootstrap/root.yaml`) syncs `argocd/root/` recursively; everything else is reached from there.
- `argocd/root/` holds only Argo CD objects (`Application`, `AppProject`). Component configuration lives in `infra/` (platform) and `apps/` (workloads).

## Layout
- `argocd/root/projects/`: AppProjects `infra`, `apps` and `pi-agents`. `sourceRepos` is an explicit allow-list; a new Helm repo must be added there or the Application is rejected.
- `argocd/root/apps/pi-agents-root.yaml` is a nested app-of-apps that syncs `k8s/argocd/` from the separate `KacperJarocki/pi-agents` repo; its child Applications use project `pi-agents`, whose `destinations` list the namespaces that repo may touch (`argocd`, `iot-security`, `iot-security-dev`, `cnpg-system`, `strimzi-system`).
- `argocd/root/infra/*.yaml` and `argocd/root/apps/*.yaml`: one Application per component, named after its Helm release.
- `infra/<component>/values.yaml` and `apps/<ns>/<app>/values.yaml`: Helm values, referenced from the Application as `$values/<path>`.
- Extra plain manifests sit next to the values in `manifests/` (or `issuers/`, `config/`, `policies/`) and are the `path` of the Git source. A directory with a `kustomization.yaml` is rendered with kustomize, otherwise every YAML file is applied as-is.
- Adding a component means: values/manifests dir + Application file + sync wave; nothing has to be registered in a central kustomization.

## Validation Commands
- `scripts/validate-local.sh` renders every Application like Argo CD would (`helm template` with the referenced values, `kubectl kustomize`, YAML parse). Needs `helm`, `kubectl`, `yq` and network access for charts. Git sources that point at other repositories are skipped.
- Single chart: `helm template <release> <chart> --repo <url> --version <ver> -n <ns> -f <values.yaml> > /dev/null`.
- Plain manifests against a reachable cluster without changing it: `kubectl apply --dry-run=server -f infra/<component>/manifests`.
- With Argo CD installed: `argocd app diff <name>` shows live vs Git for one app; `kubectl -n argocd get applications` shows sync/health state for all.

## Ordering and Sync
- Dependencies are expressed with `argocd.argoproj.io/sync-wave` on the Application files in `argocd/root/`, never by file order. Current waves: projects (-10) -> cert-manager, metallb, kyverno, external-secrets (0) -> issuers, metallb-config, kyverno-policies (1) -> traefik, longhorn, argocd (2) -> monitoring stack (3) -> pi-agents-root (4).
- The root app only advances to the next wave once every Application of the current wave is Healthy. A stuck child app blocks later waves from being created on a fresh cluster; already-created apps keep syncing independently.
- Every Application has `ServerSideApply=true` (large CRDs), `CreateNamespace=true`, automated prune + selfHeal and a `resources-finalizer` (removing the file from Git deletes the resources). The root app intentionally has no finalizer.
- Applications that apply custom resources of CRDs installed by another Application carry `SkipDryRunOnMissingResource=true`.
- Namespaces are created by Argo CD; Pod Security labels are declared via `syncPolicy.managedNamespaceMetadata` on the Application that owns the namespace (metallb for `networking`, longhorn for `longhorn-system`).

## Argo CD Itself
- Installed from the `argo-cd` Helm chart with `infra/argocd/values.yaml`; after bootstrap the `argocd` Application manages it (self-management). Keep the chart version in `argocd/root/infra/argocd.yaml`; `scripts/bootstrap-argocd.sh` reads it from there.
- `infra/argocd/values.yaml` restores the `argoproj.io/Application` health check (required for sync waves), sets annotation-based resource tracking, and ignores webhook `caBundle` diffs. Do not remove those.
- Kyverno policies under `infra/kyverno/policies/` must keep excluding the `argocd` namespace, otherwise Argo CD pods (no resource limits) are rejected.

## Repo-Specific Gotchas
- Renovate uses its `argocd` manager on `argocd/root/**/*.yaml`; chart versions must stay as `targetRevision` next to `chart:` for it to work.
- GitVersion releases run only on pushes to `main`; version bumps are driven by Conventional Commit prefixes in `GitVersion.yml` and tags are pushed as `v<MajorMinorPatch>`.
- Some manifests contain secret references, and at least one values file contains plaintext credentials; avoid pasting full rendered YAML into responses unless necessary.
- Certificates and ingresses use the `homelab.kacperjarocki.dev` / `kacperjarocki.dev` DNS zone and cert-manager ClusterIssuers defined under `infra/cert-manager/issuers/`.
- Loki values set `test.enabled: false`; chart >= 7.5.0 refuses to render otherwise when the canary is disabled.
- Loki stores chunks in the in-cluster RustFS (`infra/rustfs`, chart from charts.rustfs.com; MinIO is not an option any more, its public images were withdrawn). Loki's S3 credentials are `${S3_ACCESS_KEY_ID}`/`${S3_SECRET_ACCESS_KEY}` expanded from the `loki-s3` Secret (`-config.expand-env=true`); RustFS reads `rustfs-credentials` (`RUSTFS_ACCESS_KEY`/`RUSTFS_SECRET_KEY`). Both are created by `scripts/create-object-storage-secrets.sh`, never committed. Buckets are created by the `rustfs-buckets` Job, an Argo CD PostSync hook in `infra/rustfs/manifests/`.
- Alerting: rules in `apps/monitoring/kube-prometheus-stack/manifests/alert-rules.yaml` (own set; the chart's default rules stay off), Alertmanager -> self-hosted ntfy (`apps/monitoring/ntfy`, LAN only, `auth-default-access: deny-all`). Users and tokens live in the `ntfy-auth` and `alertmanager-ntfy` Secrets created by `scripts/create-alerting-secrets.sh` (prints the phone login; never committed). ntfy refuses to start if an `auth-access` entry names a user missing from the Secret.
- Grafana admin login comes from the `grafana-admin` Secret (`scripts/create-grafana-admin-secret.sh`, which also resets the password in Grafana's database). Do not drop `grafana.admin.existingSecret`: the chart would generate a new random password on every Argo CD render (its Helm `lookup` does not run under Argo CD) that never matches the database.
