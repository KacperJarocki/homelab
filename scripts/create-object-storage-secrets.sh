#!/usr/bin/env sh
# Creates the credential Secrets that infra/rustfs and apps/monitoring/loki
# expect but that are deliberately not in Git. Idempotent: an existing
# rustfs-credentials is kept and loki-s3 is (re)written to match it.
# Prints nothing sensitive.
set -eu

RUSTFS_NS=rustfs
LOKI_NS=monitoring

rand() { openssl rand -base64 36 | tr -d '/+=' | cut -c1-32; }

for ns in "$RUSTFS_NS" "$LOKI_NS"; do
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"
done

if kubectl -n "$RUSTFS_NS" get secret rustfs-credentials >/dev/null 2>&1; then
  echo "$RUSTFS_NS/rustfs-credentials exists, keeping it"
else
  kubectl -n "$RUSTFS_NS" create secret generic rustfs-credentials \
    --from-literal=RUSTFS_ACCESS_KEY=rustfs --from-literal=RUSTFS_SECRET_KEY="$(rand)"
fi

# Loki uses the same credentials under the names its config expands.
access=$(kubectl -n "$RUSTFS_NS" get secret rustfs-credentials -o jsonpath='{.data.RUSTFS_ACCESS_KEY}' | base64 -d)
secret=$(kubectl -n "$RUSTFS_NS" get secret rustfs-credentials -o jsonpath='{.data.RUSTFS_SECRET_KEY}' | base64 -d)
kubectl -n "$LOKI_NS" create secret generic loki-s3 \
  --from-literal=S3_ACCESS_KEY_ID="$access" --from-literal=S3_SECRET_ACCESS_KEY="$secret" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<MSG
Done. Console login (user rustfs) at https://rustfs.homelab.kacperjarocki.dev:
  kubectl -n $RUSTFS_NS get secret rustfs-credentials -o jsonpath='{.data.RUSTFS_SECRET_KEY}' | base64 -d; echo
If loki-0 was already running, restart it so it reads the new key:
  kubectl -n $LOKI_NS rollout restart statefulset loki
MSG
