#!/usr/bin/env bash
# Creates the Secrets for alerting (never committed):
#   monitoring/ntfy-auth          NTFY_AUTH_USERS / NTFY_AUTH_TOKENS for ntfy
#   monitoring/alertmanager-ntfy  token  - Alertmanager's publish token
# and prints the phone login once. Run it yourself so the password only shows
# in your terminal. Re-running rotates both credentials (restart ntfy and
# Alertmanager afterwards, or let Argo CD roll them).
#
# Needs kubectl (cluster access), htpasswd (macOS built in; apache2-utils on
# Linux) and openssl.
set -euo pipefail

ns=monitoring
# Random strings without `... | head` pipelines: under pipefail the writer's
# SIGPIPE would abort the script.
password() { local p; p="$(openssl rand -base64 36)"; p="${p//[\/+=]/}"; printf '%s' "${p:0:24}"; }

phone_password="$(password)"
alertmanager_password="$(password)"
# ntfy access tokens: "tk_" + 29 characters ([0-9a-f]).
hex="$(openssl rand -hex 16)"
alertmanager_token="tk_${hex:0:29}"

hash() { htpasswd -nbBC 10 x "$1" | cut -d: -f2- | tr -d '\n' | sed 's/^\$2y\$/$2a$/'; }

users="alertmanager:$(hash "$alertmanager_password"):user,phone:$(hash "$phone_password"):user"
tokens="alertmanager:${alertmanager_token}:Alertmanager"

kubectl -n "$ns" create secret generic ntfy-auth \
  --from-literal=NTFY_AUTH_USERS="$users" \
  --from-literal=NTFY_AUTH_TOKENS="$tokens" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ns" create secret generic alertmanager-ntfy \
  --from-literal=token="$alertmanager_token" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<MSG

Secrets ${ns}/ntfy-auth and ${ns}/alertmanager-ntfy are in place.

In the ntfy app on the phone (on the home VPN):
  Settings -> Manage users -> add user
    Service URL: https://ntfy.homelab.kacperjarocki.dev
    Username:    phone
    Password:    ${phone_password}
  then subscribe to these topics on that server:
    homelab-critical    (set it to override Do Not Disturb)
    homelab-workloads   homelab-nodes   homelab-storage
    homelab-network     homelab-monitoring   homelab-alerts (catch-all)
MSG
