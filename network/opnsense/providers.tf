# Everything is read from the environment, nothing is committed:
#   OPNSENSE_URI          https://10.20.0.1 (from the runner: LAN only)
#   OPNSENSE_API_KEY      key of the dedicated "tofu" API user
#   OPNSENSE_API_SECRET   its secret
#   OPNSENSE_ALLOW_INSECURE=true while the GUI uses the self-signed cert
provider "opnsense" {}
