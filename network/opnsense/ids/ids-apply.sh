#!/usr/bin/env sh
# Desired state for Suricata (Services > Intrusion Detection) on opnsense-1,
# applied through the OPNsense API. The OpenTofu provider has no IDS
# resources, so this script is the code for that part of the firewall.
#
#   network/opnsense/ids/ids-apply.sh            show what would change
#   network/opnsense/ids/ids-apply.sh --apply    apply it
#   ... --apply --ips                            also switch to Netmap (IPS)
#
# --ips only after Interfaces > Settings has Hardware CRC/TSO/LRO disabled
# and the firewall was rebooted; netmap with offloading on breaks WAN.
#
# Needs OPNSENSE_URI, OPNSENSE_API_KEY, OPNSENSE_API_SECRET (and
# OPNSENSE_ALLOW_INSECURE=true for the self-signed GUI cert). The API user
# needs "Services: Intrusion Detection" and "System: Settings: Cron".
# Idempotent: running it again changes nothing.
set -eu

# --- desired state -----------------------------------------------------------

# Reputation lists, practically no false positives: dropped.
DROP_RULESETS="abuse.ch.feodotracker.rules abuse.ch.sslblacklist.rules
abuse.ch.sslipblacklist.rules abuse.ch.threatfox.rules abuse.ch.urlhaus.rules
botcc.rules botcc.portgrouped.rules ciarmy.rules compromised.rules drop.rules
dshield.rules"

# Behaviour rules: alert only until a week of alerts looks clean, then move
# them to DROP_RULESETS.
ALERT_RULESETS="emerging-attack_response.rules emerging-exploit.rules
emerging-exploit_kit.rules emerging-malware.rules emerging-scan.rules
emerging-web_server.rules"

DROP_POLICY="drop-reputation"
ALERT_POLICY="alert-behaviour"
CRON_DESCRIPTION="ids rule updates"
CRON_MINUTES=0
CRON_HOURS=4

# --- plumbing ------------------------------------------------------------------

APPLY=false; IPS=false
for a in "$@"; do
  case "$a" in
    --apply) APPLY=true ;;
    --ips) IPS=true ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
for v in OPNSENSE_URI OPNSENSE_API_KEY OPNSENSE_API_SECRET; do
  eval "x=\${$v:-}"; [ -n "$x" ] || { echo "missing env: $v" >&2; exit 1; }
done
command -v jq >/dev/null || { echo "missing tool: jq" >&2; exit 1; }

K=""; [ "${OPNSENSE_ALLOW_INSECURE:-false}" = "true" ] && K="-k"
get()  { curl -sSf $K -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" "$OPNSENSE_URI/api/$1"; }
post() {
  body=${2:-}; [ -n "$body" ] || body='{}'
  curl -sSf $K -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
    -H 'Content-Type: application/json' -d "$body" "$OPNSENSE_URI/api/$1"
}
# lines of $1 that are not in $2
minus() { printf '%s\n' "$1" | grep -vxF -e "$(printf '%s\n' "$2")" -e '' || true; }
change() { echo "CHANGE $*"; changes=$((changes + 1)); }
words() { echo "$1" | tr -s ' \n' '\n' | grep -v '^$' | sort; }
changes=0

# --- 1. general settings ---------------------------------------------------------

general=$(get ids/settings/get | jq '.ids.general')
sel() { echo "$general" | jq -r --arg k "$1" '.[$k] | to_entries[] | select(.value.selected == 1) | .key' | head -1; }
want_mode=$(sel mode); $IPS && want_mode=netmap
set_general=$(jq -n --arg mode "$want_mode" '{ids: {general: {enabled: "1", syslog: "1", syslog_eve: "1", mode: $mode}}}')
for k in enabled syslog syslog_eve; do
  [ "$(echo "$general" | jq -r ".$k")" = "1" ] || change "settings: $k -> 1"
done
[ "$(sel mode)" = "$want_mode" ] || change "settings: mode $(sel mode) -> $want_mode"
if $APPLY && [ "$changes" -gt 0 ]; then post ids/settings/set "$set_general" >/dev/null; fi

# --- 2. rulesets: exactly the listed ones enabled ------------------------------------

wanted=$(words "$DROP_RULESETS $ALERT_RULESETS")
current=$(get ids/settings/list_rulesets | jq -r '.rows[] | select(.enabled == "1") | .filename' | sort)
to_enable=$(minus "$wanted" "$current")
to_disable=$(minus "$current" "$wanted")
[ -z "$to_enable" ]  || change "rulesets enable: $(echo $to_enable)"
[ -z "$to_disable" ] || change "rulesets disable: $(echo "$to_disable" | wc -l | tr -d ' ') rulesets"
if $APPLY; then
  [ -z "$to_disable" ] || post "ids/settings/toggle_ruleset/$(echo $to_disable | tr ' ' ',')/0" >/dev/null
  [ -z "$to_enable" ]  || post "ids/settings/toggle_ruleset/$(echo $to_enable | tr ' ' ',')/1" >/dev/null
  if [ -n "$to_enable$to_disable" ]; then
    echo "downloading rulesets..."
    post ids/service/update_rules >/dev/null
    # Policies can only reference rulesets that are downloaded.
    i=0
    while :; do
      have=$(get ids/settings/get_policy | jq -r '.policy.rulesets[].value' | sort)
      missing=$(minus "$wanted" "$have")
      [ -z "$missing" ] && break
      i=$((i + 1)); [ "$i" -gt 60 ] && { echo "rulesets not downloaded after 5 min: $missing" >&2; exit 1; }
      sleep 5
    done
  fi
fi

# --- 3. policies -----------------------------------------------------------------------

options=$(get ids/settings/get_policy | jq '.policy.rulesets | to_entries | map({(.value.value): .key}) | add // {}')
uuids() { for f in $(words "$1"); do echo "$options" | jq -r --arg f "$f" '.[$f] // empty'; done | sort | paste -sd, -; }
policies=$(get ids/settings/search_policy | jq '.rows')

ensure_policy() { # description prio new_action rulesets
  desc=$1; prio=$2; new=$3; rs=$(uuids "$4")
  body=$(jq -n --arg d "$desc" --arg p "$prio" --arg n "$new" --arg r "$rs" \
    '{policy: {enabled: "1", prio: $p, action: "alert", rulesets: $r, content: "", new_action: $n, description: $d}}')
  uuid=$(echo "$policies" | jq -r --arg d "$desc" '.[] | select(.description == $d) | .uuid' | head -1)
  if [ -z "$uuid" ]; then
    change "policy add: $desc ($new, prio $prio)"
    if $APPLY; then
      res=$(post ids/settings/add_policy "$body")
      echo "$res" | jq -e '.result == "saved"' >/dev/null \
        || { echo "add_policy refused: $res" >&2; exit 1; }
    fi
  else
    live=$(get "ids/settings/get_policy/$uuid" | jq -c '.policy | {
      enabled, prio,
      action: ([.action | to_entries[] | select(.value.selected == 1) | .key] | sort | join(",")),
      new_action: ([.new_action | to_entries[] | select(.value.selected == 1) | .key] | join(",")),
      rulesets: ([.rulesets | to_entries[] | select(.value.selected == 1) | .key] | sort | join(","))}')
    wantc=$(jq -nc --arg p "$prio" --arg n "$new" --arg r "$rs" \
      '{enabled: "1", prio: $p, action: "alert", new_action: $n, rulesets: $r}')
    if [ "$live" != "$wantc" ]; then
      change "policy update: $desc"
      if $APPLY; then
        res=$(post "ids/settings/set_policy/$uuid" "$body")
        echo "$res" | jq -e '.result == "saved"' >/dev/null \
          || { echo "set_policy refused: $res" >&2; exit 1; }
      fi
    fi
  fi
  return 0
}
ensure_policy "$DROP_POLICY" 1 drop "$DROP_RULESETS"
ensure_policy "$ALERT_POLICY" 2 alert "$ALERT_RULESETS"

# --- 4. daily signature update -----------------------------------------------------------

job=$(get cron/settings/search_jobs | jq -r --arg d "$CRON_DESCRIPTION" '.rows[] | select(.description == $d) | .uuid' | head -1)
if [ -z "$job" ]; then
  echo "cron job '$CRON_DESCRIPTION' not found; it is created by the IDS service" >&2
else
  cur=$(get "cron/settings/get_job/$job" | jq -c '.job | {enabled, minutes, hours}')
  want=$(jq -nc --arg m "$CRON_MINUTES" --arg h "$CRON_HOURS" '{enabled: "1", minutes: $m, hours: $h}')
  if [ "$cur" != "$want" ]; then
    change "cron '$CRON_DESCRIPTION': $cur -> $want"
    if $APPLY; then
      # The job belongs to the IDS service: OPNsense refuses any save whose
      # command/parameters differ from the stored ones, and a partial save
      # counts as different. Send the whole job back with only the schedule
      # and enabled flag changed.
      full=$(get "cron/settings/get_job/$job" | jq -c --arg m "$CRON_MINUTES" --arg h "$CRON_HOURS" '
        .job
        | with_entries(
            if (.value | type) == "object"
            then .value = ([.value | to_entries[] | select(.value.selected == 1) | .key] | join(","))
            else . end)
        | .enabled = "1" | .minutes = $m | .hours = $h
        | del(.origin)')
      # The API answers 200 even when it refuses a change; check the result.
      res=$(post "cron/settings/set_job/$job" "{\"job\": $full}")
      echo "$res" | jq -e '.result == "saved"' >/dev/null \
        || { echo "cron set_job refused: $res" >&2; exit 1; }
      post cron/service/reconfigure >/dev/null
    fi
  fi
fi

# --- done --------------------------------------------------------------------------------

if [ "$changes" -eq 0 ]; then echo "in sync"; exit 0; fi
if $APPLY; then
  post ids/service/reconfigure >/dev/null
  echo "applied $changes change(s); Suricata reconfigured"
else
  echo "$changes change(s) pending; run with --apply"
fi
