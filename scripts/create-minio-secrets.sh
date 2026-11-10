#!/usr/bin/env sh
# Creates the credential Secrets that infra/minio and apps/monitoring/loki
# expect but that are deliberately not in Git. Idempotent: existing Secrets
# are left untouched. Prints nothing sensitive.
set -eu

MINIO_NS=minio
LOKI_NS=monitoring

rand() { openssl rand -base64 36 | tr -d '/+=' | cut -c1-32; }
have() { kubectl -n "$1" get secret "$2" >/dev/null 2>&1; }

kubectl get namespace "$MINIO_NS" >/dev/null 2>&1 || kubectl create namespace "$MINIO_NS"
kubectl get namespace "$LOKI_NS" >/dev/null 2>&1 || kubectl create namespace "$LOKI_NS"

if have "$MINIO_NS" minio-root; then
  echo "minio/minio-root exists, keeping it"
else
  kubectl -n "$MINIO_NS" create secret generic minio-root \
    --from-literal=rootUser=admin --from-literal=rootPassword="$(rand)"
fi

if have "$MINIO_NS" minio-user-loki && have "$LOKI_NS" loki-s3; then
  echo "minio/minio-user-loki and monitoring/loki-s3 exist, keeping them"
else
  key=$(rand)
  have "$MINIO_NS" minio-user-loki || kubectl -n "$MINIO_NS" create secret generic minio-user-loki \
    --from-literal=secretKey="$key"
  # Must hold the same key the MinIO user is created with.
  have "$LOKI_NS" loki-s3 || kubectl -n "$LOKI_NS" create secret generic loki-s3 \
    --from-literal=S3_ACCESS_KEY_ID=loki --from-literal=S3_SECRET_ACCESS_KEY="$key"
fi

cat <<MSG
Done. Console login (user admin):
  kubectl -n $MINIO_NS get secret minio-root -o jsonpath='{.data.rootPassword}' | base64 -d; echo
MSG
