#!/usr/bin/env bash
# Creates monitoring/grafana-admin (admin-user / admin-password, never
# committed), sets the same password in the running Grafana's database and
# prints the login. Grafana only reads the admin password on first start, so
# both have to change together. Re-running rotates the password.
#
# Needs kubectl (cluster access) and openssl.
set -euo pipefail

ns=monitoring
deploy=kube-prometheus-stack-grafana
user=admin
pw="$(openssl rand -base64 36)"
pw="${pw//[\/+=]/}"
pw="${pw:0:28}"

kubectl -n "$ns" create secret generic grafana-admin \
  --from-literal=admin-user="$user" \
  --from-literal=admin-password="$pw" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$ns" exec "deploy/$deploy" -c grafana -- \
  grafana cli --homepath /usr/share/grafana admin reset-admin-password "$pw" >/dev/null

cat <<MSG

Secret ${ns}/grafana-admin is in place and Grafana's admin password was reset.

  URL:      https://grafana.homelab.kacperjarocki.dev
  Username: ${user}
  Password: ${pw}
MSG
