#!/usr/bin/env sh
# One-time bootstrap of Argo CD on a cluster. Idempotent; safe to re-run.
#
#   1. apply the Kyverno policies (they must exclude the argocd namespace,
#      otherwise the Enforce policies block Argo CD pods that carry no limits)
#   2. helm install the argo-cd chart with the same values the self-managing
#      Application uses later
#   3. apply the root app-of-apps, which takes over from here
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ARGOCD_APP=argocd/root/infra/argocd.yaml
CHART_REPO=$(grep -E '^\s+- repoURL: https://argoproj' "$ARGOCD_APP" | awk '{print $3}')
CHART_VERSION=$(grep -A2 'chart: argo-cd' "$ARGOCD_APP" | grep targetRevision | awk '{print $2}')
FIELD_MANAGER=argocd-controller   # same manager Argo CD uses for server-side apply

echo ">> cluster: $(kubectl config current-context)"
echo ">> argo-cd chart: $CHART_REPO $CHART_VERSION"

if kubectl get crd clusterpolicies.kyverno.io >/dev/null 2>&1; then
  echo ">> applying Kyverno policies (argocd namespace exclusions)"
  kubectl apply --server-side --field-manager "$FIELD_MANAGER" --force-conflicts \
    -f infra/kyverno/policies/
fi

echo ">> installing Argo CD"
helm upgrade --install argocd argo-cd \
  --repo "$CHART_REPO" --version "$CHART_VERSION" \
  --namespace argocd --create-namespace \
  --values infra/argocd/values.yaml \
  --wait --timeout 10m

echo ">> applying root application"
kubectl apply --server-side --field-manager "$FIELD_MANAGER" -f argocd/bootstrap/root.yaml

cat <<MSG

Argo CD is up. Initial admin password:
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

Watch the rollout:
  kubectl -n argocd get applications -w
  kubectl -n argocd port-forward svc/argocd-server 8080:80   # until the ingress/cert is ready
MSG
