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
rand() { LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c "$1"; }

phone_password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
alertmanager_password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
# ntfy access tokens: "tk_" + 29 characters.
alertmanager_token="tk_$(rand 29)"

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
  then subscribe to topic "homelab-alerts" on that server.
MSG
