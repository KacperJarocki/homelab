# OPNsense as code

OpenTofu configuration for the OPNsense firewall (`opnsense-1`, `10.20.0.1`),
using the [`browningluke/opnsense`](https://registry.opentofu.org/providers/browningluke/opnsense)
provider (REST API).

```
versions.tf     provider pin + S3 backend (in-cluster RustFS)
encryption.tf   state/plan encryption (enforced)
providers.tf    provider, configured only via OPNSENSE_* env vars
aliases.tf      firewall aliases
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

1. **OPNsense API user.** System > Access > Users: user `tofu`, no GUI login,
   privileges limited to what is managed here (Firewall: Alias, Firewall:
   Rules, Services: Unbound, Services: Kea DHCP, ... add as needed) plus
   *Diagnostics: Configuration History* for the backup step. Create an API key
   for it.
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
5. **Lock file.** Run `tofu init` once (see below) and commit the generated
   `.terraform.lock.hcl` with hashes for both runners:
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

## Rules of thumb

- Adopt before you add: import what exists, get to an empty plan, then change.
- The anti-lockout rule and the rules that let the LAN reach the GUI/SSH stay
  out of OpenTofu, so a bad apply can always be undone by hand.
- One concern per PR; the plan is what you approve in the `opnsense`
  environment, read it.
