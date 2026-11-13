#!/usr/bin/env sh
# Renders every Argo CD Application under argocd/root the way Argo CD would:
#   - Helm sources: helm template with the referenced $values files
#   - Git sources: kustomize build, or a YAML parse for plain-manifest directories
# Needs: helm, kubectl, yq (mikefarah). Network access is required for charts.
# RENDER_DIR=<dir>: also keep the rendered manifests there, one file per
# Application source (<app>.<source>.yaml); the Kubescape CI job scans them.
set -eu
RENDER_DIR=${RENDER_DIR:-}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

for tool in helm kubectl yq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 1; }
done

status=0
fail() { echo "FAIL $1" >&2; status=1; }

# Where rendered output goes: /dev/null, or a file in RENDER_DIR.
out() { # app index
  if [ -n "$RENDER_DIR" ]; then
    echo "$RENDER_DIR/$(basename "$1" .yaml).$(echo "$2" | tr -c 'a-z0-9\n' '-').yaml"
  else
    echo /dev/null
  fi
}

render_helm() { # app ns index
  app=$1; ns=$2; i=$3
  repo=$(yq ".$i.repoURL" "$app")
  chart=$(yq ".$i.chart" "$app")
  version=$(yq ".$i.targetRevision" "$app")
  release=$(yq ".$i.helm.releaseName // .metadata.name" "$app")
  set --
  for vf in $(yq ".$i.helm.valueFiles[]? | sub(\"^\\\$values/\", \"\")" "$app"); do
    [ -f "$vf" ] || { fail "$app: values file $vf not found"; return; }
    set -- "$@" --values "$vf"
  done
  # A repoURL without a scheme is an OCI registry (Argo CD convention).
  case "$repo" in
    *://*) set -- "$chart" --repo "$repo" "$@" ;;
    *)     set -- "oci://$repo/$chart" "$@" ;;
  esac
  if helm template "$release" "$@" --version "$version" \
       --namespace "$ns" --include-crds >"$(out "$app" "$i")" 2>"$tmp"; then
    echo "ok   helm      $chart@$version ($app)"
  else
    fail "$app: helm template $chart@$version"; cat "$tmp" >&2
  fi
}

render_git() { # app index
  app=$1; i=$2
  repo=$(yq ".$i.repoURL" "$app")
  case "$repo" in
    *github.com/kacperjarocki/homelab*) ;;
    *) echo "skip external  $repo ($app)"; return ;;
  esac
  dir=$(yq ".$i.path" "$app")
  [ -d "$dir" ] || { fail "$app: path $dir not found"; return; }
  if [ -f "$dir/kustomization.yaml" ]; then
    kubectl kustomize "$dir" >"$(out "$app" "$i")" 2>"$tmp" && echo "ok   kustomize $dir ($app)" || { fail "$app: kustomize $dir"; cat "$tmp" >&2; }
  else
    dest=$(out "$app" "$i"); : >"$dest"
    for f in $(find "$dir" -name '*.yaml' | sort); do
      yq -e '.kind' "$f" >/dev/null 2>"$tmp" || { fail "$f: invalid manifest"; cat "$tmp" >&2; }
      { echo "---"; cat "$f"; } >>"$dest"
    done
    echo "ok   manifests $dir ($app)"
  fi
}

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
[ -z "$RENDER_DIR" ] || mkdir -p "$RENDER_DIR"

for app in $(find argocd/root argocd/bootstrap -name '*.yaml' | sort); do
  yq -e '.apiVersion == "argoproj.io/v1alpha1"' "$app" >/dev/null 2>"$tmp" || { fail "$app: not an Argo CD manifest"; cat "$tmp" >&2; continue; }
  [ "$(yq '.kind' "$app")" = "Application" ] || continue
  ns=$(yq '.spec.destination.namespace' "$app")
  if [ "$(yq '.spec.source // ""' "$app")" != "" ]; then
    srcs=spec.source
  else
    n=$(yq '.spec.sources | length' "$app"); srcs=""; i=0
    while [ "$i" -lt "$n" ]; do srcs="$srcs spec.sources.$i"; i=$((i+1)); done
  fi
  for src in $srcs; do
    if [ "$(yq ".$src.chart // \"\"" "$app")" != "" ]; then
      render_helm "$app" "$ns" "$src"
    elif [ "$(yq ".$src.path // \"\"" "$app")" != "" ]; then
      render_git "$app" "$src"
    fi
  done
done

# Schema validation of the Application/AppProject objects themselves, when a
# cluster with the Argo CD CRDs is reachable.
if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  kubectl apply --dry-run=server -R -f argocd/root -f argocd/bootstrap >/dev/null 2>"$tmp" \
    && echo "ok   server dry-run argocd/" || { fail "server dry-run argocd/"; cat "$tmp" >&2; }
fi

[ "$status" -eq 0 ] && echo "local validation passed" || echo "local validation FAILED" >&2
exit "$status"
