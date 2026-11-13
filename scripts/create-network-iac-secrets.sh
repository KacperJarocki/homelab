#!/usr/bin/env sh
# Creates the Secrets that infra/arc-runners and network/opnsense expect but
# that are deliberately not in Git:
#   arc-runners/arc-github-app   GitHub App credentials for ARC
#   arc-runners/opnsense-tofu    OPNsense API key, RustFS S3 credentials and
#                                the OpenTofu state passphrase (runner env)
#   opnsense/opnsense-backup     API key + RustFS credentials for the daily
#                                config.xml backup CronJob
#
# Input (environment):
#   GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_PRIVATE_KEY_FILE
#   OPNSENSE_API_KEY, OPNSENSE_API_SECRET
#   OPNSENSE_URI              optional, default https://10.20.0.1
#   OPNSENSE_ALLOW_INSECURE   optional, default true (self-signed GUI cert)
#
# Idempotent: Secrets are (re)written from the input, except the state
# passphrase, which is generated once and then always kept. Run
# scripts/create-object-storage-secrets.sh first (rustfs-credentials).
set -eu

NS=arc-runners
BACKUP_NS=opnsense
RUSTFS_NS=rustfs

need() { eval "v=\${$1:-}"; [ -n "$v" ] || { echo "missing env: $1" >&2; exit 1; }; }
for v in GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY_FILE \
         OPNSENSE_API_KEY OPNSENSE_API_SECRET; do need "$v"; done
[ -f "$GITHUB_APP_PRIVATE_KEY_FILE" ] || { echo "not a file: $GITHUB_APP_PRIVATE_KEY_FILE" >&2; exit 1; }
kubectl -n "$RUSTFS_NS" get secret rustfs-credentials >/dev/null 2>&1 \
  || { echo "$RUSTFS_NS/rustfs-credentials missing, run scripts/create-object-storage-secrets.sh" >&2; exit 1; }

kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"

kubectl -n "$NS" create secret generic arc-github-app \
  --from-literal=github_app_id="$GITHUB_APP_ID" \
  --from-literal=github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
  --from-file=github_app_private_key="$GITHUB_APP_PRIVATE_KEY_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

get() { kubectl -n "$1" get secret "$2" -o jsonpath="{.data.$3}" 2>/dev/null | base64 -d; }

new_passphrase=false
passphrase=$(get "$NS" opnsense-tofu TF_VAR_state_passphrase || true)
if [ -z "$passphrase" ]; then
  passphrase=$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-48)
  new_passphrase=true
fi

kubectl -n "$NS" create secret generic opnsense-tofu \
  --from-literal=OPNSENSE_URI="${OPNSENSE_URI:-https://10.20.0.1}" \
  --from-literal=OPNSENSE_ALLOW_INSECURE="${OPNSENSE_ALLOW_INSECURE:-true}" \
  --from-literal=OPNSENSE_API_KEY="$OPNSENSE_API_KEY" \
  --from-literal=OPNSENSE_API_SECRET="$OPNSENSE_API_SECRET" \
  --from-literal=AWS_ACCESS_KEY_ID="$(get "$RUSTFS_NS" rustfs-credentials RUSTFS_ACCESS_KEY)" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(get "$RUSTFS_NS" rustfs-credentials RUSTFS_SECRET_KEY)" \
  --from-literal=TF_VAR_state_passphrase="$passphrase" \
  --dry-run=client -o yaml | kubectl apply -f -

# Daily config.xml backup CronJob (infra/opnsense-backup): same API user,
# same RustFS credentials, no state passphrase.
kubectl get namespace "$BACKUP_NS" >/dev/null 2>&1 || kubectl create namespace "$BACKUP_NS"
kubectl -n "$BACKUP_NS" create secret generic opnsense-backup \
  --from-literal=OPNSENSE_URI="${OPNSENSE_URI:-https://10.20.0.1}" \
  --from-literal=OPNSENSE_ALLOW_INSECURE="${OPNSENSE_ALLOW_INSECURE:-true}" \
  --from-literal=OPNSENSE_API_KEY="$OPNSENSE_API_KEY" \
  --from-literal=OPNSENSE_API_SECRET="$OPNSENSE_API_SECRET" \
  --from-literal=AWS_ACCESS_KEY_ID="$(get "$RUSTFS_NS" rustfs-credentials RUSTFS_ACCESS_KEY)" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(get "$RUSTFS_NS" rustfs-credentials RUSTFS_SECRET_KEY)" \
  --dry-run=client -o yaml | kubectl apply -f -

if [ "$new_passphrase" = true ]; then
  cat <<MSG
New OpenTofu state passphrase generated. Store it in the password manager now;
without it the state in s3://tofu-state cannot be read:
  kubectl -n $NS get secret opnsense-tofu -o jsonpath='{.data.TF_VAR_state_passphrase}' | base64 -d; echo
MSG
fi
echo "Done. Runner pods pick up changes on their next job (they are ephemeral)."
