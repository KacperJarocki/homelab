# OPNsense as code

OpenTofu configuration for the OPNsense firewall (`opnsense-1`, `10.20.0.1`),
using the [`browningluke/opnsense`](https://registry.opentofu.org/providers/browningluke/opnsense)
provider (REST API).

```
versions.tf     provider pin + S3 backend (in-cluster RustFS)
encryption.tf   state/plan encryption (enforced)
providers.tf    provider, configured only via OPNSENSE_* env vars
aliases.tf      firewall aliases
dns.tf          Unbound host overrides (imported)
firewall.tf     filter rules, LAN + PRD (imported; "FW GUI" stays manual)
imports.tf      import blocks for adopting existing objects
```

## How changes reach the firewall

`.github/workflows/opnsense.yml`:

| Trigger | Runner | What runs |
|---|---|---|
| pull request touching `network/opnsense/**` | `ubuntu-latest` | `fmt -check`, `validate` (no credentials, no LAN access) |
| push to `main`, `workflow_dispatch` | `homelab-arm64` (ARC, in-cluster) | `plan` -> encrypted plan artifact |
| same, only when the plan has changes | `homelab-arm64`, environment `opnsense` (manual approval) | backup of `config.xml` to RustFS, `apply` of exactly that plan |

The self-hosted runner never runs code from pull requests: this repo is public
and the runner sits in the LAN next to the firewall API.

## One-time setup

1. **OPNsense API user.** System > Access > Groups > `+`: group `iac`, no
   members except `tofu`, with exactly these privileges (names as the GUI
   shows them, checked against the 26.1 ACL files):

   | Privilege | Covers |
   |---|---|
   | Firewall: Alias: Edit | `api/firewall/alias/*` (CRUD + reconfigure) |
   | Firewall: Aliases | alias search/get/export |
   | Firewall: Categories | `api/firewall/category/*` |
   | Firewall: Rules [new] | `api/firewall/filter/*` (rules, savepoint, apply) |
   | Services: Unbound | `api/unbound/*` (overrides, settings, service reconfigure) |
   | Diagnostics: Configuration History | `api/core/backup/*` (pre-apply and daily backups) |
   | Status: Interfaces | `api/interfaces/overview/*` (read, drift check) |
   | Interfaces: Bridge | `api/interfaces/bridge_settings/*` (drift check reads bridge members) |

   Then System > Access > Users > `tofu`: member of `iac` **only** (not
   `readonly`: `user-config-readonly` makes every write fail, and not
   `admins`), no GUI login needed, one API key. Add privileges here only when
   a new resource type moves into this directory (e.g. *Services: Kea DHCP*).
2. **GitHub App for ARC.** Settings > Developer settings > GitHub Apps, owned
   by your account, no webhook, repository permission *Administration:
   Read & write* (and *Metadata: Read*). Install it on `homelab` only. Note the
   App ID and installation ID, download the private key.
3. **Secrets in the cluster** (never committed):
   ```sh
   GITHUB_APP_ID=... GITHUB_APP_INSTALLATION_ID=... \
   GITHUB_APP_PRIVATE_KEY_FILE=~/Downloads/app.private-key.pem \
   OPNSENSE_API_KEY=... OPNSENSE_API_SECRET=... \
   scripts/create-network-iac-secrets.sh
   ```
   On the first run it generates the state passphrase and prints the command
   that reads it back: store it in the password manager, it is the only way
   to read the state.
4. **GitHub repo settings.**
   - Settings > Environments > `opnsense`: required reviewer = you, deployment
     branches = `main` only.
   - Settings > Actions > General > *Fork pull request workflows from outside
     collaborators*: **Require approval for all external contributors**.
5. **Lock file** is committed (`linux_arm64`, `linux_amd64`, `darwin_arm64`).
   After a provider bump, refresh it with
   `tofu providers lock -platform=linux_arm64 -platform=linux_amd64 -platform=darwin_arm64`.

## Running locally (and break-glass)

The S3 API of RustFS is cluster-internal, so reach it with a port-forward. This
is also the way out when the runner is down, e.g. because a rule cut the
cluster off: OPNsense itself is still reachable from the LAN.

```sh
kubectl -n rustfs port-forward svc/rustfs-svc 9000:9000 &
eval "$(kubectl -n arc-runners get secret opnsense-tofu -o json \
  | jq -r '.data | to_entries[] | "export \(.key)=\(.value | @base64d | @sh)"')"
export AWS_ENDPOINT_URL_S3=http://127.0.0.1:9000
export OPNSENSE_URI=https://10.20.0.1   # if the in-cluster value differs
cd network/opnsense && tofu init && tofu plan
```

If the cluster is gone completely, OPNsense keeps its own configuration history
(System > Configuration > History) and every apply leaves a copy of the
previous `config.xml` under `s3://tofu-state/backups/`.

## Interfaces: checked, not managed

Interface assignments and addresses are legacy pages without a write API in
OPNsense 26.1 (`interfaces_assign.php`, `interfaces.php`), and the provider
has no bridge resource. `infra/opnsense-ops` checks them hourly against
`infra/opnsense-ops/interfaces-expected.json`; any difference fires
`OPNsenseInterfaceDrift` (ntfy topic network). Changing an interface on
purpose = change the firewall and that JSON in the same go.

## Settings the provider cannot manage (GUI, keep this list current)

### Remote syslog -> Loki

System > Settings > Logging > Remote > `+`:
enabled, transport **UDP(4)**, applications: *filter*, *suricata* and
*system* (empty = everything), levels: info and above, hostname
**10.20.30.51**, port **514**, **RFC5424** checked, description `loki`.
Also Firewall > Settings > Advanced (or Logging): log packets matched by the
default block rules.

In Grafana (Loki): `{job="opnsense/syslog"}`, IDS alerts
`{job="opnsense/syslog", app="suricata"} | json`. The receiver is
`loki.source.syslog "opnsense"` in `apps/monitoring/alloy/config/config.alloy`
behind the `alloy-syslog` LoadBalancer.

### IDS/IPS (Suricata), blocking

1. Interfaces > Settings: disable **Hardware CRC**, **Hardware TSO** and
   **Hardware LRO** (netmap/IPS breaks with offloading), reboot.
2. Services > Intrusion Detection > Administration > Settings (state on
   2026-11-13: enabled, mode *PCAP live mode (IDS)* = detect only, WAN,
   Hyperscan, syslog off): set mode **Netmap (IPS)**, keep interface
   **WAN** (netmap on the `bridge0`/PRD side is not reliable; *Divert (IPS)*
   would need `divert-to` on the filter rules, which the provider cannot
   set), promiscuous off, pattern matcher *Hyperscan*, home networks stay
   RFC1918, turn on **Enable syslog alerts** and **Enable eve syslog
   output**.
3. Rulesets, policies and the daily signature update are code:
   `network/opnsense/ids/ids-apply.sh` (the provider has no IDS resources).
   It keeps exactly the listed rulesets enabled, maintains the policies
   `drop-reputation` (abuse.ch + ET reputation lists -> **drop**) and
   `alert-behaviour` (ET emerging-* behaviour rules -> alert), and enables
   the *ids rule updates* cron job at 04:00. Without `--apply` it only
   prints what would change; `--ips` additionally sets Netmap mode.
   API user privileges: *Services: Intrusion Detection*, *System: Settings:
   Cron*. After a week of clean alerts in Grafana, move rulesets from
   `ALERT_RULESETS` to `DROP_RULESETS` and run it again.

Unused plugins: `os-isc-dhcp` (no DHCP server configured, no leases) and
`os-wazuh-agent` (disabled) can be removed in System > Firmware > Plugins.

## Rules of thumb

- Adopt before you add: import what exists, get to an empty plan, then change.
- The anti-lockout rule and the rules that let the LAN reach the GUI/SSH stay
  out of OpenTofu, so a bad apply can always be undone by hand.
- One concern per PR; the plan is what you approve in the `opnsense`
  environment, read it.
