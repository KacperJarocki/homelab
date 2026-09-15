#!/usr/bin/env sh
set -eu

run_checks() {
  kubectl kustomize cluster > /dev/null
  kubectl kustomize flux/flux-system > /dev/null

  flux build kustomization cluster \
    --path ./cluster \
    --kustomization-file ./flux/flux-system/cluster-kustomization.yaml \
    --dry-run > /dev/null

  flux build kustomization longhorn-system \
    --path ./infra/longhorn-system \
    --kustomization-file ./flux/flux-system/longhorn-system.yaml \
    --dry-run > /dev/null

  flux build kustomization kyverno \
    --path ./infra/policy/kyverno \
    --kustomization-file ./flux/flux-system/kyverno.yaml \
    --dry-run > /dev/null

  flux build kustomization policies \
    --path ./infra/policy/policies \
    --kustomization-file ./flux/flux-system/policy.yaml \
    --dry-run > /dev/null

  flux build kustomization certmanager-issuer \
    --path ./infra/certmanager/certIssuers \
    --kustomization-file ./flux/flux-system/certmanager-issuer.yaml \
    --dry-run > /dev/null
}

if [ "${1:-}" = "--loop" ]; then
  while ! run_checks; do
    printf 'local validation failed, retrying in 2s...\n' >&2
    sleep 2
  done
else
  run_checks
fi

printf 'local validation passed\n'
