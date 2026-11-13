# homelab

Single source of truth for a k3s homelab, managed with the GitOps approach using
[Argo CD](https://argo-cd.readthedocs.io/). Everything the cluster runs is declared
here; Argo CD keeps the cluster in sync with `main`.

## Hardware

- raspberry pi 5 8gb

## Layout

```
argocd/
  bootstrap/root.yaml   root "app of apps", applied once by scripts/bootstrap-argocd.sh
  root/                 everything the root Application syncs (recursively)
    projects/           AppProjects: infra, apps, pi-agents
    infra/              one Application per platform component
    apps/               one Application per workload
infra/<component>/      values.yaml (+ manifests/ or other plain-manifest dirs)
apps/<ns>/<app>/        values.yaml (+ manifests/, config/)
network/opnsense/       OpenTofu for the OPNsense firewall (applied by CI on the in-cluster runner)
scripts/                bootstrap, secrets, local validation
docs/                   runbooks
```

An Application for a Helm chart uses two sources: the chart from its Helm repo and
this Git repo (`ref: values`) that supplies `$values/.../values.yaml` and, when
present, a directory of extra manifests (certificates, pools, policies):

```yaml
sources:
  - repoURL: https://charts.longhorn.io
    chart: longhorn
    targetRevision: 1.11.2
    helm:
      releaseName: longhorn
      valueFiles:
        - $values/infra/longhorn/values.yaml
  - repoURL: https://github.com/kacperjarocki/homelab.git
    targetRevision: main
    ref: values
    path: infra/longhorn/manifests
```

## Sync order

Ordering is driven by `argocd.argoproj.io/sync-wave` on the Applications in
`argocd/root/`. The root app waits for every Application in a wave to be Healthy
before creating the next wave.

| wave | applications                                                  | why                                   |
|------|---------------------------------------------------------------|---------------------------------------|
| -10  | AppProjects                                                   | referenced by every Application       |
| 0    | cert-manager, metallb, kyverno, external-secrets              | controllers that bring CRDs           |
| 1    | cert-manager-issuers, metallb-config, kyverno-policies        | custom resources of the wave-0 CRDs   |
| 2    | traefik, longhorn, argocd                                     | need a ClusterIssuer and an IP pool   |
| 3    | kube-prometheus-stack, loki, alloy                            | need longhorn storage                 |
| 4    | pi-agents-root (nested app-of-apps from the pi-agents repo)   | needs cert-manager and longhorn       |

## Secrets outside Git

Credentials are never committed. Before the first sync of `rustfs`/`loki` on a
fresh cluster run `scripts/create-object-storage-secrets.sh`; it creates:

| namespace    | secret               | used by                                              |
|--------------|----------------------|------------------------------------------------------|
| `rustfs`     | `rustfs-credentials` | RustFS root key (chart `secret.existingSecret`, bucket job, console login) |
| `monitoring` | `loki-s3`            | same key under `S3_ACCESS_KEY_ID`/`S3_SECRET_ACCESS_KEY`, read by Loki at start-up |

The pi-agents repo has its own (`rustfs-credentials` in `iot-security`, `iot-security-external-services`).

## Other repositories

`argocd/root/apps/pi-agents-root.yaml` is a nested app-of-apps: it syncs `k8s/argocd/`
from [pi-agents](https://github.com/KacperJarocki/pi-agents), which defines its own
Applications (operators + the platform chart) in the `pi-agents` AppProject. That
project is defined here and pins which repos and namespaces the tenant may use.

## Day-to-day

- Add a workload: create `apps/<ns>/<name>/values.yaml`, add
  `argocd/root/apps/<name>.yaml` (copy a neighbour), pick a sync wave.
- Add a platform component: same under `infra/` and `argocd/root/infra/`; add its
  Helm repo URL to `argocd/root/projects/infra.yaml`.
- Validate locally before pushing: `scripts/validate-local.sh` (needs `helm`,
  `kubectl`, `yq`).
- Chart versions live in `argocd/root/**/*.yaml` and are bumped by Renovate.
- Fresh cluster or disaster recovery: `scripts/bootstrap-argocd.sh`.

## Access

- UI: https://argocd.homelab.kacperjarocki.dev
- CLI: `argocd login argocd.homelab.kacperjarocki.dev --grpc-web`
- Initial admin password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`
