# Migration runbook: Flux CD -> Argo CD

One-off cutover of the live cluster. Workloads are **not** redeployed: Flux is
removed without garbage-collecting anything, then Argo CD adopts the existing
resources (annotation-based tracking, server-side apply).

Prerequisites on the workstation: `kubectl` (context `k3s-home-1`), `helm`, `flux`,
`argocd`, `yq`, and the migration PR merged into `main`.

## 0. Before merging

```sh
git checkout main && git pull
scripts/validate-local.sh          # on the feature branch: every chart must render
flux get all -A                    # note what is currently reconciled
helm ls -A                         # note current chart versions
```

Known state on the cluster that is *not* in this repo and therefore will not be
managed by Argo CD:

- Flux `GitRepository/pi-agents` + `Kustomization/pi-agents-streaming` came from the
  separate `KacperJarocki/pi-agents` repo. That repo now ships `k8s/argocd/` and is
  picked up by `argocd/root/apps/pi-agents-root.yaml` (wave 4), so its operators and the
  platform chart are adopted the same way as everything here. `gateway-agent`,
  previously applied by hand from `k8s/gateway`, becomes Argo-managed too.
- `cilium` and `gateway-api-crd` Helm releases in `kube-system` (installed by hand).

## 1. Stop Flux (nothing gets deleted)

`flux uninstall` suspends and strips finalizers from every Kustomization and
HelmRelease before deleting them, so the Deployments, Helm-rendered resources, PVCs
etc. stay in place.

```sh
flux suspend kustomization --all
for hr in $(kubectl get helmrelease -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); do
  kubectl patch helmrelease -n "${hr%/*}" "${hr#*/}" --type merge -p '{"spec":{"suspend":true}}'
done
flux uninstall --namespace flux-system      # answers y; keeps workloads
kubectl get ns flux-system                  # should be gone
helm ls -A                                  # releases still listed: expected
```

## 2. Merge the PR

Merge `feat/argocd-migration` into `main`. Nothing reconciles at this point.

```sh
git checkout main && git pull
```

## 3. Bootstrap Argo CD

```sh
scripts/bootstrap-argocd.sh
```

What it does, in order:

1. `kubectl apply --server-side` of `infra/kyverno/policies/` so the Enforce
   policies exclude the `argocd` namespace (Argo CD pods have no limits).
2. `helm upgrade --install argocd` with `infra/argocd/values.yaml`.
3. `kubectl apply` of `argocd/bootstrap/root.yaml`.

Then watch:

```sh
kubectl -n argocd get applications -w
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80   # http://localhost:8080 until the ingress works
```

Expected: wave 0 apps go Synced/Healthy within a minute or two (they only adopt
what is already there). Wave 2 `argocd` takes over the Helm-installed Argo CD.
Wave 3 upgrades Loki from 7.3.0 to 7.5.0 (the version Flux had been failing to
apply; fixed with `test.enabled: false`).

## 4. Verify

```sh
argocd login argocd.homelab.kacperjarocki.dev --grpc-web --username admin
argocd app list
argocd app diff kube-prometheus-stack      # should be empty or caBundle-only noise
kubectl get certificate -A                 # all Ready, incl. argocd/argocd
kubectl get pods -A | grep -v Running
```

If an app is OutOfSync because of a field a Helm hook or controller mutates,
prefer `ignoreDifferences` on that Application over disabling selfHeal.

## 5. Clean up Flux leftovers (optional, after a few days)

Helm release secrets written by Flux's helm-controller are inert under Argo CD
(Argo CD does not use Helm releases). Removing them only tidies `helm ls`:

```sh
for r in cert-manager:cert-manager external-secrets:external-secrets kyverno:kyverno-system \
         longhorn:longhorn-system metallb:networking traefik:networking \
         kube-prometheus-stack:monitoring loki:monitoring alloy:monitoring; do
  kubectl -n "${r#*:}" delete secret -l "owner=helm,name=${r%%:*}"
done
```

Keep the `argocd` release secret in `argocd` until the `argocd` Application is
Synced; afterwards it is inert too.

Labels `helm.toolkit.fluxcd.io/*` and `kustomize.toolkit.fluxcd.io/*` remain on
adopted resources. They are harmless and disappear on the next full re-render.

## Rollback

Before step 2 the old layout is still on `main`: `flux bootstrap github --owner
kacperjarocki --repository homelab --branch main --path flux` restores Flux. After
step 3, rollback means reverting the merge commit and re-bootstrapping Flux the same
way; Argo CD can be removed with `helm uninstall argocd -n argocd` (Applications
carry finalizers: delete the `root` app first, then the children with
`argocd app delete --cascade=false`).
